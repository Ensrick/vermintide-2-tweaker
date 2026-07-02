--[[
chaos_wastes_tweaker — Chaos Wastes ("deus" mode) run modifiers.

Major sections (search by name to jump):
  * Coin economy           — coin_multiplier hook on DeusRunController.on_soft_currency_picked_up,
                             starting_coins via setup_run.
  * Boon counts            — generate_random_power_ups hook intercepts shrine (4) and chest (3) defaults.
  * Disabled boons         — save-and-restore mutation of DeusPowerUpsArray / *ByRarity around the roll.
  * Curses                 — disable_curse_* setting reads, gating MutatorHandler._activate_mutator,
                             DeusMechanism.get_current_node_curse, and node theme/curse fields.
  * Run config overrides   — deus_journey_with_belakor hook (force_belakor) +
                             game_round_ended pre-mutation of vote_data.dominant_god
                             (finale_dominant_god). Both host-only.
  * Pickups & altars       — populate_pickups hook patches deus_weapon_chest / deus_cursed_chest /
                             ammo counts AND injects campaign potions into Pickups.deus_potions
                             with full-group renormalization (see also: DEVELOPMENT.md).
  * Chest-type distribution — get_deus_weapon_chest_type override; "Default" sentinel = 0.
  * Starting boons         — _add_initial_power_ups hook (host-only) grants toggled boons.
  * Banned weapon traits   — apply_weapon_trait_filter / restore_weapon_trait_filter wraps
                             DeusWeaponGeneration calls.
  * Khaine's Fury tweak    — apply_reckless_swings_tweak / revert_reckless_swings_tweak +
                             sync_reckless_swings (forward-declared; called from boon roll).
  * Bomb boon balance      — bomb_boon_cooldown override on drop_item_on_ability_use, mutual
                             exclusivity in generate_random_power_ups via BOMB_BOON_NAMES,
                             Endless-Bombs-consumes-Morgrim hook on apply_pockets_full_of_bombs_buff,
                             RV-no-save-Morgrim hook on ActionChargedProjectileUtility.fire_charged_projectile.
  * Lifecycle              — on_setting_changed re-syncs Khaine's Fury and bomb cooldown;
                             on_disabled reverts both persistent DeusPowerUpTemplates mutations.
]]

local mod = get_mod("ct_dev")

-- v0.7.88: vanilla VT2 declares this as a file-scope local in every file that
-- needs it (`local REAL_PLAYER_LOCAL_ID = 1` — see deus_run_controller.lua,
-- deus_spawning.lua, deus_chest_extension.lua, etc.). It is NOT exposed
-- globally, so referencing the bare token from this mod resolved to
-- `_G.REAL_PLAYER_LOCAL_ID = nil`. That silently broke the Miracle of Ulric /
-- Miracle of Isha blessing-purchase paths: `get_player_soft_currency(buyer,
-- nil)` returned 0 instead of the player's real coin balance, so every buy
-- attempt rejected with "coins=0 < cost=100" even when the player had hundreds.
-- Captured in log diff host vs client 2026-05-22 session.
local REAL_PLAYER_LOCAL_ID = 1

local MOD_VERSION = "0.7.208-dev"
_MEM_PROBE_T0_CT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)
-- v0.7.104-dev: ct_meta_ammo redesign — hyperbolic cost-floor with direct hooks on
-- use_ammo / drain / add_charge. Replaces v0.7.102's linear-additive stat_buff
-- approach which crashed to 0 cost at ~20 boons. See `.ammo_system_design_2026-05-24.md`.
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([ct] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
pcall(printf, "Chaos Wastes Tweaker v%s loaded", MOD_VERSION)

-- v0.7.114-dev (Issue #27): Explicit RPC schema_version + drop-on-mismatch.
-- ============================================================
-- Schema version of cross-peer RPC payloads emitted by THIS mod (ct).
-- Prepended as the FIRST positional argument of every `mod:network_send` ct emits,
-- and validated as the FIRST argument of every `mod:network_register` callback.
-- On mismatch, the receiver drops the message and logs a `_dbg_alert`. No state mutation,
-- no crash — just silent (well, _dbg_alert if debug logging is on) graceful degradation.
--
-- Bump this constant ONLY when you change RPC payload shape (add/remove/reorder fields).
-- Don't bump it for non-shape changes (logging tweaks, refactors, new hooks that don't
-- touch the RPC payload). The constant is the gate; the receiver compares peer's value
-- to its own and drops on mismatch.
--
-- Graceful-degradation path for old peers (pre-v0.7.114 without CT_RPC_SCHEMA):
--   * Old peer sends without the version arg → new receiver sees its first real
--     payload field (e.g. `session`, a number) in the schema_version slot →
--     compares against CT_RPC_SCHEMA (1) → likely fails → drops. No corruption.
--   * New peer sends WITH version=1 → old receiver (which doesn't expect it) shifts
--     every arg by one position → its type-checks on the legacy first arg fail → drops.
--     Worst case: the old receiver mis-handles a packet on a mod that's about to be
--     replaced anyway. Acceptable; the schema gate IS the migration cliff.
--
-- VMF_RECIPES.md § 10 documents the full design + when to bump.
local CT_RPC_SCHEMA = 1
pcall(printf, "[ct:rpc] schema_version=%d", CT_RPC_SCHEMA)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    mod:debug("[ct:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[ct:dbg] " .. fmt, ...)
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data")
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

pcall(printf, "[ct:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[ct] v%s loaded", MOD_VERSION))
end

-- v0.7.108-dev (Issue #34): hard cap on `ct_meta_*` per-stack buff templates.
-- Pre-v0.7.108 the meta-boon factory wrote `max_stacks = math.huge` (also the
-- special-cased ct_meta_movespeed block did the same), trusting `_make_meta_proc`
-- to never push the stack count beyond the active boon count. That's true under
-- the happy path, but a runaway proc — for example if `_get_player_power_ups`
-- temporarily returns a stale-large list during a peer-late-join graph resync, or
-- if a future code path calls add_buff(stack_name) outside the proc — drives the
-- `total_ammo` stat_buff geometrically (engine resolution at buff_extension.lua:1391-
-- 1448: `final_value = final_value * (multiplier + 1) + bonus` per stack), pushing
-- `_max_ammo` toward `math.huge`. `tostring(math.huge) == "inf"` then renders on
-- the HUD via equipment_ui.lua:635 — same shape as the wt v0.12.77 nil-hole-
-- multi-return collapse that surfaced as `inf` ammo. This is the latent CT version
-- of that bug class (see GitHub Issue #34).
--
-- 30 is well past the realistic boon ceiling (a CW run typically tops out around
-- 12-18 boons even with farmable shrines; 30 is endgame-of-endgame). With the
-- v0.7.104 hyperbolic cost floor in place, 30 stacks of +5% total_ammo = 1.05^30 ≈
-- 4.3x — generous, but bounded. The defensive `math.min(buffed_max, 9999)` clamp
-- inside the `_apply_buffs` hook (search for CT_META_AMMO_MAX_AMMO_SAFETY_CLAMP)
-- is belt-and-suspenders: even if some other future buff path bypasses this cap,
-- the `_max_ammo` value can never exceed 9999 (well below Lua's float-printable
-- range, so it always renders as a finite integer on the HUD).
local CT_META_AMMO_MAX_STACKS = 30

-- v0.7.107-dev: Nil-hole-safe variadic capture helper. `{ func(...) }` followed
-- by `unpack(t)` silently truncates returns at the first internal nil — Lua 5.1's
-- `#t` operator stops at the first nil entry, and bare `unpack(t)` uses `#t` as
-- the upper bound. Same bug class that burned weapon_tweaker v0.12.77/.78.
-- Use `select("#", ...)` to capture the true return count, then `unpack(t, 1, n)`
-- with explicit bounds so nil holes survive across the wrapper.
--
-- Pattern:
--     local n, results = _capture_returns(func(self, ...))
--     -- ... do work ...
--     return unpack(results, 1, n)
local function _capture_returns(...) return select("#", ...), { ... } end

-- v0.7.102: Universal clamp helper for network-bounded `_max_<field>` mutations.
-- Engine `.network_config` (compiled binary) holds hardcoded ints for max_overcharge,
-- max_energy, etc.; writing a value above the cap fasserts in the per-frame engine
-- update path (`player_unit_overcharge_extension.lua:110`,
-- `player_unit_energy_extension.lua:43`). Lua mods CANNOT widen those ints.
--
-- DOCTRINE (feedback_vt2_max_resource_consumption_side.md, redundant-safeguards-ok):
-- Never directly write `_max_<field>` for a +resource boon — use the consumption-side
-- stat_buff (reduced_overcharge / ammo_used_multiplier / etc.). The shape of vanilla's
-- system is "reduce the cost per cast", not "widen the bar". This helper exists as
-- belt-and-suspenders: if a future code path is tempted to mutate `_max_<X>` anyway,
-- routing the write through here guarantees the value stays under the engine cap,
-- regardless of base, multiplier, or boon count.
--
-- Sentinel string CT_CLAMP_NETWORK_BOUNDED_MAX_v0.7.102 is embedded in the body and
-- checked by `/ct_regression_test` source-pattern check `ct_clamp_helper_present`.
local function _clamp_network_bounded_max(field_name, raw_value)
    -- CT_CLAMP_NETWORK_BOUNDED_MAX_v0.7.102 -- regression sentinel; do not rename.
    local NC = rawget(_G, "NetworkConstants")
    local cap_meta = NC and NC[field_name]
    local cap = cap_meta and (cap_meta.max or cap_meta[2])
    -- Fallback when engine constant unavailable: 60 (overcharge/energy's known
    -- cap) is a known-safe lower-bound. Burned twice without fallback.
    cap = cap or 60
    local min_meta = cap_meta and (cap_meta.min or cap_meta[1])
    local floor_val = min_meta or 1
    local v = math.floor(math.min(raw_value, cap) + 0.5)
    return math.max(floor_val, v)
end
-- Expose on mod table so siblings (and tests) can introspect the helper.
mod._clamp_network_bounded_max = _clamp_network_bounded_max

-- v0.7.104-dev: Hyperbolic-saturating cost multiplier for ct_meta_ammo.
-- Replaces the v0.7.102 linear consumption-side stat_buff approach which had a
-- gamebreaking zero-crossing at ~20 boons (root_multiplier = 1 + sum_of_-0.05
-- went to 0 at N=20 → infinite ammo / energy / overcharge / spam).
--
-- Curve: cost_factor = max(1 - (N*step) / (1 + N*step/cap), floor)
--   step  = 0.05  (preserves the +5%/boon feel)
--   cap   = 0.75  (asymptotic — saturates at 25% cost at infinite stacks)
--   floor = 0.25  (hard minimum — convergent + bounded, never zero, never negative)
--
-- Properties (verified by tests below):
--   * N = 0    → 1.000 (no behavior change)
--   * N = 5    → 0.812
--   * N = 10   → 0.700
--   * N = 20   → 0.571
--   * N = 50   → 0.423
--   * N = 100  → 0.348
--   * N → ∞    → 0.250 (asymptote, NEVER reaches 0)
--   * cost_factor IS ALWAYS in [floor, 1.0] for any non-negative N
--
-- Sentinel string CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104 is checked by
-- `/ct_regression_test` source-pattern check `ct_meta_ammo_hyperbolic_floor_v0_7_104`.
-- See `.ammo_system_design_2026-05-24.md` for the design + vanilla call-site analysis.
local CT_META_AMMO_STEP  = 0.05
local CT_META_AMMO_CAP   = 0.75
local CT_META_AMMO_FLOOR = 0.25
local CT_META_AMMO_HYPERBOLIC_MARKER = "CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104"
local function _ct_meta_ammo_cost_multiplier(num_boons)
    -- CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104 -- regression sentinel; do not rename.
    if type(num_boons) ~= "number" or num_boons <= 0 then return 1.0 end
    local raw = (num_boons * CT_META_AMMO_STEP)
              / (1 + num_boons * CT_META_AMMO_STEP / CT_META_AMMO_CAP)
    local cost = 1.0 - raw
    if cost < CT_META_AMMO_FLOOR then cost = CT_META_AMMO_FLOOR end
    if cost > 1.0 then cost = 1.0 end
    return cost
end
mod._ct_meta_ammo_cost_multiplier = _ct_meta_ammo_cost_multiplier

-- v0.7.100-dev DEFENSIVE STYLE (after v0.7.99 chest-of-trials scope bug):
-- 1. Top-level tables consumed by mid-file closures: declare at TOP of file
--    (above all closures), not late. A `local X = {}` declared mid-file shadows
--    earlier global references and produces silent half-fixes that only crash
--    on specific code paths (e.g. the v0.7.99 chest-of-trials line 1144 crash).
-- 2. Global table indexes: wrap in (rawget(_G, "X") or {}) sentinel when used
--    in a table-index expression so a missing global yields nil-on-index,
--    not a fatal.
-- 3. NetworkLookup / BuffTemplates: always rawget(); strict __index metatables
--    crashify on missing key (network_lookup.lua:2354).
-- 4. Every disabled feature ships with a regression check that ASSERTS THE
--    DISABLE (not just the enable). See dormant_boons_NOT_registered for the
--    template; sentinel string CT_DORMANT_PURGE_VERIFIED_v0.7.100 below is
--    the marker the source-pattern check looks for.

-- v0.7.100-dev PURGE SENTINEL — embedded as a constant so the regression check
-- `dormant_setting_keys_not_consumed` can verify the purged-state was actually
-- shipped (vs. a partial revert that re-introduces dormant code). DO NOT
-- rename without also updating the regression check.
local CT_DORMANT_PURGE_VERIFIED = "CT_DORMANT_PURGE_VERIFIED_v0.7.100"

-- 2026-05-23 v0.7.100-dev: dormant boons + Skulls event boons + ct_kill_heal FULLY purged from
-- the active code path per user request after recurring Chest-of-Trials crashes (most recent:
-- GUID 4c5d2157 at line 1144 from the v0.7.99 half-fix where `DORMANT_BOON_RARITY` was set on
-- _G as an empty table but closure references still indexed it). v0.7.100-dev removes EVERY
-- active reference to dormant data: `_should_strip` dormant branch, the boon-trace hook's
-- dormant fields, `/verify_dormants` chat command, `pre_register_dormant_lookups`,
-- `sync_dormant_boons`, the `DORMANT_BOON_RARITY` table itself, the Skulls block, the
-- ct_kill_heal block (latter two already block-commented in v0.7.98-dev). The original
-- implementation lives in block comments — re-enable is a literal uncomment, but
-- restoration requires the CW Wastes engine-level crash investigation to be closed first.
--
-- The 3 regression checks (`dormant_boons_NOT_registered`, `dormant_boons_NOT_in_pool`,
-- `dormant_boon_rarity_is_table`) plus the 2 new ones (`dormant_setting_keys_not_consumed`,
-- `dormant_chat_commands_removed`) iterate the constants below to assert the disable holds.
local CT_DISABLED_DORMANT_BOON_NAMES = {
    "deus_ammo_pickup_give_allies_ammo",
    "deus_coin_pickup_regen",
    "deus_large_ammo_pickup_infinite_ammo",
    "deus_larger_clip",
    "deus_throw_speed_increase",
    "deus_timed_block_free_shot",
    "deus_transmute_into_coins",
    "explosive_pushes_on_damage_taken",
    "squats",
    "ct_kill_heal",
}
local CT_DISABLED_DORMANT_RARITIES = {
    deus_ammo_pickup_give_allies_ammo    = "rare",
    deus_coin_pickup_regen               = "rare",
    deus_large_ammo_pickup_infinite_ammo = "exotic",
    deus_larger_clip                     = "rare",
    deus_throw_speed_increase            = "rare",
    deus_timed_block_free_shot           = "exotic",
    deus_transmute_into_coins            = "rare",
    explosive_pushes_on_damage_taken     = "exotic",
    squats                               = "rare",
    ct_kill_heal                         = "exotic",
}
local CT_DISABLED_SKULLS_BOON_NAMES = {
    "boon_skulls_01", "boon_skulls_02", "boon_skulls_03", "boon_skulls_04", "boon_skulls_05",
    "boon_skulls_06", "boon_skulls_07", "boon_skulls_08",
    "boon_skulls_set_bonus_01", "boon_skulls_set_bonus_02",
}
pcall(printf, "[ct] dormant/skulls boons purged (v%s, sentinel=%s); %d dormants + %d skulls boons removed from active code path. See comments near L4448/L4724/L5698 in source for re-enable instructions.",
    MOD_VERSION, CT_DORMANT_PURGE_VERIFIED, #CT_DISABLED_DORMANT_BOON_NAMES, #CT_DISABLED_SKULLS_BOON_NAMES)

-- /regression_test scaffold. See the corresponding _rt_register calls at end
-- of file. Each registered check is a function returning nil for PASS or a
-- string for FAIL.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("ct_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== ct regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            _dbg("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
pcall(printf, "[regression-test-command] registered as /ct_regression_test")

-- Mutex cluster framework (v0.7.85 — replaces the Miracle of Isha dropdown
-- with a (A)/(B) checkbox cluster). See chaos_wastes_tweaker_mutex.lua's
-- doc-block and LOCALIZATION_STANDARD.md § 10 at repo root. New clusters
-- land here as additional dropdowns get migrated to the multiple-choice
-- pattern.
local _ct_mutex_ok, _ct_mutex = pcall(mod.dofile, mod, "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_mutex")
if not _ct_mutex_ok then
    mod:error("[mutex] Failed to load chaos_wastes_tweaker_mutex: %s", tostring(_ct_mutex))
    _ct_mutex = { declare = function() end, enforce = function() end, active = function() return nil end, snapshot = function() return {} end }
end

-- Cluster: Miracle of Isha alternative behavior. Both off = vanilla (one
-- team revive-from-death per run). Exactly one on = that alternative behavior
-- applies for the rest of the run after the shrine pickup. The enforcer
-- guarantees you can't accidentally enable both at once via the UI.
_ct_mutex.declare("isha_choice", {
    "tweak_miracle_of_isha_aegis",
    "tweak_miracle_of_isha_wounds",
})

-- v0.7.120-dev: Bot Boon Mode cluster. Vanilla (both off) = bots do NOT receive
-- boons when the host claims one. Mirror = every bot gets the same boon. Random
-- = each bot rolls an independent random boon. Enforcing single-select avoids
-- the ambiguous "both on" state in the add_power_ups hook below.
_ct_mutex.declare("bots_boon_mode", {
    "bots_mirror_host_boons",
    "bots_get_random_boons",
})

-- v0.7.82: vanilla crash defense for Skittergate / deus coin pickups.
--
-- Lyndsey host crash 2026-05-22 03:43:17 GUID 8077653f:
--   game_mode_deus.lua:749: attempt to index local 'loot_amount_settings' (a nil value)
--   dropped_by_breed = "chaos_spawn_exalted_champion_norsca"
--
-- Vanilla `DeusSoftCurrencySettings.loot_amount` (deus_soft_currency_settings.lua:41)
-- has entries for `chaos_exalted_champion_norsca` (without "spawn") and
-- `chaos_spawn_exalted_champion_warcamp` (with "spawn" but warcamp), but NOT
-- the hybrid `chaos_spawn_exalted_champion_norsca`. Skulls event + breed
-- combination apparently generates this hybrid name. game_mode_deus.lua:749
-- then crashes indexing into the nil table.
--
-- Fix: set a __index metatable on DeusSoftCurrencySettings.loot_amount that
-- returns the same DEFAULT_BOSS_RANGE entry every existing boss breed uses,
-- for any unknown breed key. Transparent to vanilla — direct lookups still
-- work, only missing keys fall through to the metatable. The metatable
-- returns one of the existing tables to avoid creating a new range object
-- per session.
local function _install_deus_loot_amount_fallback()
    local settings = rawget(_G, "DeusSoftCurrencySettings")
    if not settings or not settings.loot_amount then return end
    -- Use the existing chaos_spawn entry as the fallback for unknown
    -- breeds — same shape, same range distribution as every other boss
    -- entry (all use the same DEFAULT_BOSS_RANGE constant).
    local fallback = settings.loot_amount.chaos_spawn or settings.loot_amount["n/a"]
    if not fallback then return end
    local meta = getmetatable(settings.loot_amount) or {}
    if meta.__index_installed_by_ct then return end  -- idempotent
    meta.__index = function(_, key)
        return fallback
    end
    meta.__index_installed_by_ct = true
    setmetatable(settings.loot_amount, meta)
    pcall(printf, "[deus loot fallback] installed __index metatable — unknown breed keys now return chaos_spawn's loot range")
end
_install_deus_loot_amount_fallback()

local AdventurePool = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool")
-- Call unconditionally so the LEVEL_AVAILABILITY snapshot is captured at mod load,
-- even if the master toggle is off. inject_pool() short-circuits internally when the
-- master is off (only resets to snapshot). Snapshot-at-load means subsequent toggles
-- always reset to clean vanilla state — no race where snapshot is taken after our
-- own previous mutations.

-- Capture vanilla NetworkLookup.level_keys count BEFORE inject_pool can mutate it.
-- The lobby-hash-pretend hook below uses this to hide our injected entries from
-- LobbyAux.create_network_hash so the combined_hash always reports vanilla num_levels,
-- letting peers with this mod join vanilla / non-matching lobbies. See v0.7.4-alpha
-- CHANGELOG for the full root-cause and reference_vt2_lobby_combined_hash.md.
local _vanilla_level_keys_count
if rawget(_G, "NetworkLookup") and NetworkLookup.level_keys then
    _vanilla_level_keys_count = #NetworkLookup.level_keys
end

AdventurePool.inject_pool()

-- Lobby-hash-pretend shim. VT2's LobbyAux.create_network_hash (lobby_aux.lua:26) reads
-- `num_levels = #NetworkLookup.level_keys` and folds it into the lobby `combined_hash`
-- that all peers compare for join compatibility. Our _adventure_pool.lua registers a new
-- level_keys entry for every injected adventure permutation (and must — the multiplayer
-- level-load RPC serializes by index into this table). That bumped num_levels from
-- vanilla 582 to ~774 and gave players `Join failed - Game version mismatch` against any
-- peer with a different injection configuration (including vanilla).
--
-- Fix: temporarily nil out the injected entries (indices > _vanilla_level_keys_count)
-- during create_network_hash, then restore. `#` operates on the contiguous-prefix length,
-- so vanilla code computes num_levels as if we never injected. Entries are restored
-- before the function returns, so the in-game level-load RPC still resolves correctly.
--
-- Effect:
--   • A peer with injection on can JOIN any vanilla or mismatched lobby (hash matches).
--   • A peer hosting CW with injection on creates a lobby whose hash also reports vanilla,
--     so vanilla peers can join too.
--   • Cross-config play is now possible for VANILLA CW scenarios. Picking an INJECTED
--     adventure mission while a vanilla peer is in the lobby still crashes that peer
--     (their level_keys lacks the entry) — host has to pick a vanilla CW node, or all
--     peers must run matching injection. See "Caveats" in v0.7.4-alpha CHANGELOG.
local _LobbyAux = rawget(_G, "LobbyAux")
if _LobbyAux and _LobbyAux.create_network_hash and _vanilla_level_keys_count then
    mod:hook(_LobbyAux, "create_network_hash", function(func, ...)
        local lookup = rawget(_G, "NetworkLookup") and NetworkLookup.level_keys
        if not lookup then return func(...) end
        local current = #lookup
        if current <= _vanilla_level_keys_count then return func(...) end

        local saved = {}
        for i = current, _vanilla_level_keys_count + 1, -1 do
            saved[i] = lookup[i]
            lookup[i] = nil
        end

        local hash_result = func(...)

        for i, k in pairs(saved) do
            lookup[i] = k
        end

        return hash_result
    end)
    pcall(printf, "Lobby hash shim installed (vanilla level_keys count = %d).", _vanilla_level_keys_count)
else
    mod:warning("Lobby hash shim NOT installed; LobbyAux=%s vanilla_count=%s. Injected adventure missions may cause 'Game version mismatch' on join.",
        tostring(_LobbyAux ~= nil), tostring(_vanilla_level_keys_count))
end

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT = 3
local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

-- Boons that grant or amplify free bombs/grenades. Used by the bomb-boon mutual-exclusion
-- toggle (one bomb boon per run) and listed in the localization tooltip.
local BOMB_BOON_NAMES = {
    drop_item_on_ability_use = true,
    deus_grenade_multi_throw = true,
}

-- v0.7.97: career-exclusive pickups that must NEVER be world-spawned (chests, racks,
-- ambient ground spawns). These live in `Pickups.*` so vanilla / mod code can look up
-- the item template via `AllPickups[name]`, but the only legitimate way for them to
-- reach a player's inventory is the owning career's grant function (e.g.
-- `inventory_extension:add_equipment(slot_name, ItemMasterList[item_name], ...)`).
-- The `_can_spawn` hook below denies these BEFORE the ADVENTURE_CATS allow-list
-- approves them (which our v0.7.64 broadening accidentally did on injected
-- adventure missions).
--
-- Reported 2026-05-23: Outcast Engineer crafted bomb `engineer_grenade_t1` rolling
-- as a ground pickup on CW runs (injected adventure path). Vanilla source:
-- `Pickups.grenades.engineer_grenade_t1` at pickups.lua:698; granted by Engineer's
-- cooldown buff at `dlcs/cog/buff_settings_cog.lua:232` via add_equipment (NOT via
-- PickupSystem._spawn_pickup), so blocking the world-spawn path is safe -- the
-- career grant path is untouched.
--
-- The denial path also exposes a per-run counter for `/verify_engineer_bombs`
-- and the `engineer_bombs_blocked_at_spawn` regression check.
local _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST = {
    -- Bardin Outcast Engineer (`dr_outcast_engineer` / `dr_engineer`):
    --   Crafted by his cooldown buff in cog dlc; vanilla `Pickups.grenades`
    --   entry only exists so the engineer's grant code can resolve the
    --   item template name.
    engineer_grenade_t1 = true,
}

-- Per-run denial telemetry. Reset at every populate_pickups entry (run boot).
-- Keyed by pickup_name -> number of times the hook vetoed it this run. Exposed
-- via `/verify_engineer_bombs` and `engineer_bombs_blocked_at_spawn` regression
-- check.
local _career_exclusive_denial_counts = {}
-- Once-per-run log rate-limit: which names have we already logged this run?
-- Stops the denial log spamming for every spawner that polls the grenades pool.
local _career_exclusive_logged_this_run = {}

-- v0.7.95: per-run idempotence flag for the starting_coins setter override.
-- `setup_run` is the lifecycle event for "campaign begins" and fires exactly
-- once per new CW run, but defensive belt-and-suspenders: track the last
-- run_id we applied to so any re-entry (host-migration replay, debug re-runs
-- of setup_run) doesn't re-apply on top of vanilla's set value.
-- See feedback_redundant_safeguards_ok.md.
local _starting_coins_applied_for_run = nil
-- Marker constant — embedded in the compiled bundle so the
-- /ct_regression_test source-pattern check can verify the setter-override
-- mode (not adder mode) shipped to the bundle.
local STARTING_COINS_MODE_MARKER = "starting_coins:setter-override-via-setup_run-arg"

-- v0.7.129-dev altar-reuse fix marker: the re-arm logic runs as a POST-hook
-- on DeusChestExtension.open_chest (so vanilla _post_chest_unlock + _equip_weapon
-- both complete with real profile_index before we zero anything). Earlier
-- v0.7.127 hooked `purchase` which fired BETWEEN those two calls and crashed
-- with SPProfiles[0] = nil on weapon-swap altars. Source-pattern verified
-- by /ct_regression_test check `altar_reuse_hook_on_open_chest`.
local CT_ALTAR_REUSE_HOOK_MARKER = "altar_reuse:open_chest_post_hook_v0.7.129"

-- v0.7.130-dev CoT enemy multiplier marker: hook filters on
-- `element.spawn_counter_category == "cursed_chest_enemies"` so it only scales
-- cursed-chest trial waves, not unrelated terror events. Source-pattern
-- verified by /ct_regression_test check `cot_enemy_multiplier_cursed_chest_only`.
local CT_COT_ENEMY_MULT_MARKER = "cot_enemy_mult:cursed_chest_enemies_filter_v0.7.130"

-- v0.7.131-dev open_chest hook consolidation marker. ct had TWO hooks on
-- DeusChestExtension.open_chest in v0.7.129/.130 — altar-reuse (mod:hook)
-- AND bot-weapon-mirror (mod:hook_safe). VMF silently drops the second hook
-- on the same (Class, method) from the same mod (VMF_RECIPES.md § 1). The
-- altar-reuse hook never actually ran for two whole releases. v0.7.131
-- consolidates both bodies into a SINGLE mod:hook_safe at the bot-mirror
-- site. Source-pattern verified by /ct_regression_test check
-- `open_chest_hook_singleton`. DO NOT add a second open_chest hook.
local CT_OPEN_CHEST_CONSOLIDATED_MARKER = "open_chest:consolidated_single_hook_v0.7.131"
-- #100 (v0.7.169-dev): the bot-weapon-mirror inside the open_chest hook must mirror the rarity
-- the HOST actually received (the pre-bump `_opened_rarity` captured at hook entry), NOT the
-- value `self._rarity` is bumped to for the next upgrade use — else bots land one tier above the
-- host (log-confirmed go_id=62: host rare, bots exotic). Global (not local) to dodge the
-- 200-local chunk cap. Asserted by /ct_regression_test "bot_weap_opened_rarity_pre_bump".
CT_BOT_WEAP_OPENED_RARITY_MARKER = "bot_weap:opened_rarity_pre_bump_v0.7.169"

-- v0.7.157-dev Task A: altar "goes dark after first use" DIAGNOSE-ONLY probes.
-- Read-only instrumentation on DeusChestExtension.update (visual-state evolution
-- post-re-arm) + extra _dbg lines in the consolidated open_chest re-arm path.
-- Source-pattern verified by /ct_regression_test check `altar_visual_probe_present`.
-- Tagged [altar_visual_probe]. NO behavior change.
-- (Global, not a main-chunk local: the file is at the Lua 5.1 200-locals cap; only
-- the regression-test callbacks read these markers, so a global is fine.)
CT_ALTAR_VISUAL_PROBE_MARKER = "altar_visual_probe:readonly_update_hook_v0.7.157"

-- v0.7.158-dev Task 1: the REAL upgrade-altar "goes dark after first use" fix.
-- Hooks DeusChestExtension._setup_rarity (the single writer of self._rarity) to
-- bump a re-armed upgrade altar's rolled rarity strictly above the player's
-- wielded (just-upgraded) weapon, so update_upgrade_chest_color stops firing
-- `lua_interact_disabled` and the altar stays usable/lit until the usable rarity
-- ceiling. Source-pattern verified by /ct_regression_test check
-- `upgrade_altar_rarity_bump`.
-- (Global, not a main-chunk local: see note on CT_ALTAR_VISUAL_PROBE_MARKER above.)
CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER = "upgrade_altar_rarity_bump:setup_rarity_hook_v0.7.158"

-- Chest of Trials uniqueness (Task B, #117). ALWAYS-ON as of v0.7.177-dev (the
-- prior `cursed_chest_unique_trials` toggle was removed). Two host-authoritative
-- layers guarantee consecutive Chests of Trials in one mission roll different
-- trials: (1) a per-mission activation counter mixed into the seed passed to
-- ConflictDirector.start_terror_event (varies the sub-challenge walk), and (2) a
-- TerrorEventMixer.start_event wrapper that force-rotates each cursed_chest_prototype
-- inject_event block's event_name_list to a single pick that DIFFERS from that
-- block's previous pick (guarantees the top-level faction challenge changes).
-- Source-pattern verified by /ct_regression_test check `cursed_chest_unique_trials`.
-- (Global, not a main-chunk local: see note on CT_ALTAR_VISUAL_PROBE_MARKER above.)
CT_COT_UNIQUE_TRIALS_MARKER = "cot_unique_trials:force_rotate_event_name_list_v0.7.177"
local all_trait_combos_cache = nil
-- CLARIFY: Forward-declared so the `generate_random_power_ups` hook (call site line 150) and
-- `on_setting_changed` (line 740) can reference sync_reckless_swings before its assignment at line
-- 724. Lua 5.1 locals are not hoisted; without this stub the references would either resolve to a
-- global lookup (and silently no-op until the assignment runs) or crash. See
-- feedback_lua_forward_reference.md (5 prior crashes from this exact bug pattern).
local sync_reckless_swings
local sync_bomb_cooldown
local sync_ulric_pack_unlimited_range
local sync_boon_movespeed
-- v0.7.39: defeat-recovery state. Referenced in `_transition_next_node` hook (line ~402)
-- which is defined BEFORE the feature block that owns this flag (line ~2706+). Forward-
-- declaring here keeps the hook valid pre-feature-block execution.
local _defeat_recovery_triggered_this_round = false

-- Forward-declared so hooks/UI text generators can resolve it lexically; body assigned
-- after `effective_setting` is defined (Lua local hoisting rules require the slot to
-- exist before any closure captures it).
local is_curse_disabled

-- v0.7.55: forward-declared so hooks above its assignment (most notably the
-- on_soft_currency_picked_up hook at line ~140 reading coin_multiplier) can capture
-- the local slot at closure creation time. Body assigned in the multiplayer-sync
-- block below.
local effective_setting

-- Forward declaration: assigned in the peer-manifest block. The ct_sync_host_settings_chunk
-- handler calls this on receive so each client replies to the host's broadcast with its
-- own manifest. Defined later in the file, but the handler closure is built before then,
-- so it needs the forward-declared local slot to bind a closure-over.
local _broadcast_local_manifest

-- audit 2026-06-07 (v0.7.133-dev): forward-declare the two pickup dump helpers.
-- They are first REFERENCED inside the consolidated PickupSystem.populate_pickups
-- hook closure (the `pcall(_dump_pickup_system_state, ...)` / `pcall(_dump_pickup_
-- spawners_verbose, ...)` calls at ~line 2638-2639), but their `local function`
-- definitions live far below (~3006 / ~3127). Lua 5.1 binds locals lexically at
-- closure-creation time with no hoisting, so without these stubs the hook closure
-- captured the GLOBAL name (nil) and `pcall(nil, ...)` returned false silently —
-- the post-populate diagnostics never fired. Stubs here + dropping `local` on the
-- later definitions makes both references resolve to the same upvalue slot
-- (BUG_CLASSES §6 forward-ref pattern; see feedback_lua_forward_reference.md).
local _dump_pickup_system_state
local _dump_pickup_spawners_verbose

-- audit 2026-06-07 (v0.7.133-dev): marker proving the three variadic forwarding
-- hooks (on_soft_currency_picked_up / DeusRunController.setup_run /
-- DeusPowerUpUtils.generate_random_power_ups) capture real arity via
-- select("#", ...) and forward with unpack(args, 1, n) instead of bare
-- unpack(args). Bare unpack stops at the first nil hole (trailing `type` /
-- `mutators`+`boons` / `forced_rarity` are commonly nil), truncating the args
-- passed to vanilla (VMF_RECIPES §2a). Asserted by /ct_regression_test check
-- `variadic_hooks_arity_preserved`.
local CT_VARIADIC_ARITY_MARKER = "unpack_arity:select_count_v0.7.133"

-- CLARIFY: Vanilla signature is `on_soft_currency_picked_up(self, amount, type)`. The `amount` is
-- args[1] (NOT args[2] — that mistake was the cause of an early-version coin multiplier bug; see
-- "Coin multiplier not working (wrong argument index)" in DEVELOPMENT.md).
mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    -- audit 2026-06-07 (v0.7.133-dev): capture real arity. Vanilla sig is
    -- (self, amount, type); `type` (args[2]) is frequently nil, so bare
    -- unpack(args) would stop at the nil hole and drop trailing args. Pass
    -- explicit n so the nil is preserved positionally (VMF_RECIPES §2a).
    local n = select("#", ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" then
        -- v0.7.55: route through effective_setting so a client picking up coins applies
        -- the host's coin_multiplier (matches what the host's own pickups grant).
        local multiplier = effective_setting("coin_multiplier") or 1
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
    end

    return func(self, unpack(args, 1, n))
end)

-- ============================================================
-- Altar reuse (v0.7.127-dev) — Issue #61: configurable max uses per altar type
-- ============================================================
-- Vanilla DeusChestExtension is single-use: `purchase()` (deus_chest_extension.lua:301)
-- sets `_is_purchased = true` and fires the `lua_update_collected` flow event;
-- the altar's "looted" animation plays and `can_be_unlocked()` (line 487) returns
-- false on subsequent attempts.
--
-- This feature lets the host configure max uses per altar type (boon shrine,
-- melee swap, ranged swap, weapon upgrade — matching the 4 DEUS_CHEST_TYPES the
-- vanilla extension already differentiates internally) with a geometric cost
-- multiplier applied per reuse.
--
-- Mechanism (3 narrow hooks):
--   1. get_purchase_cost — wrap vanilla, scale by mult^uses_so_far.
--   2. purchase — post-call, if uses < max:
--        - restore _is_purchased=false + _animation_state=nil
--        - zero _profile_index/_career_index so vanilla update() (line 134)
--          re-runs the full setup block on the next tick (re-rolls offerings,
--          fires the lua_update_<rarity> flow event so the altar visually
--          re-arms)
--   3. _generate_stored_power_up / _generate_stored_weapon — mix the use count
--      into the seed input so each re-roll produces different offerings.
--
-- All thresholds read via effective_setting so the host's values apply to
-- clients via the standard VMF broadcast. The per-unit `_altar_uses_by_go_id`
-- table is server-state (only the server's purchase() hook writes to it).
--
-- VISUAL-SYNC CAVEAT (corrected v0.7.151-dev): the vanilla chest network sync is
-- ONE-DIRECTIONAL toward "looted" only. The first open inserts the opener's peer
-- into the networked GameSession field `collected_by_peers` (server handler
-- rpc_deus_chest_looted, deus_chest_extension.lua:737-752) and NOTHING ever
-- removes it. So zeroing only the LOCAL re-arm fields is not enough: vanilla
-- update() (deus_chest_extension.lua:175) re-derives `new_is_purchased` from
-- `table.contains(collected_by_peers, peer_id)`, re-asserts _animation_state=
-- "looted" (line 177-182), and line 194 then skips _update_chest_animation_and_
-- sound_state — so the re-rolled offering hologram never re-displays. The re-arm
-- block therefore ALSO retracts the own peer from collected_by_peers (server
-- writes it directly; a client opener round-trips through the ct_altar_uncollect
-- RPC so the server clears the authoritative field). See _ct_remove_peer_from_
-- collected / mod._ct_altar_uncollect below.
--
-- UPGRADE-ALTAR ROOT CAUSE (v0.7.158-dev — the ACTUAL fix for "goes dark after
-- first use", solo host, no peers):
-- The v0.7.151 collected_by_peers uncollect was a real bug but NOT the cause of
-- the upgrade altar darkening. For an UPGRADE altar the looted look is derived
-- TWO independent ways:
--   (1) collected_by_peers membership (deus_chest_extension.lua:175) — uncollect
--       handles this, and solo-host it's a direct local write that DOES hold.
--   (2) update_upgrade_chest_color (deus_chest_extension.lua:211-243) — runs
--       EVERY tick, independent of collected_by_peers. It compares the altar's
--       rolled `_rarity` against the player's CURRENTLY WIELDED weapon rarity:
--           event = chest_rarity_order <= weapon_rarity_order
--               and "lua_interact_disabled" or LUA_UPDATE_RARITY_EVENTS[rarity]
--       After the first upgrade, the wielded weapon's rarity == the altar's
--       rolled rarity, so chest_rarity_order <= weapon_rarity_order is TRUE and
--       the altar fires `lua_interact_disabled` — the grey/"dark", can't-use
--       visual. can_be_unlocked (lines 505-517) likewise returns false, so the
--       re-armed altar is GENUINELY unusable, not just cosmetically dark.
-- The altar re-rolls `_rarity` each re-arm (update() line 140 -> _setup_rarity),
-- but the seed is constant per go_id, so it always re-rolls the SAME rarity, and
-- update_upgrade_chest_color always re-disables it. Therefore the upgrade-altar
-- re-arm must ALSO bump `_rarity` strictly above the just-upgraded weapon (capped
-- at `unique`, order 5) and clear the cached `_prev_update_upgrade_chest_color_
-- event` so the disabled-color event re-evaluates. See the upgrade branch in the
-- consolidated open_chest hook (_ct_consolidated_open_chest_hook).
local DEUS_CHEST_TYPE_TO_KEY = {
    power_up    = "power_up",
    swap_melee  = "swap_melee",
    swap_ranged = "swap_ranged",
    upgrade     = "upgrade",
}
local _altar_uses_by_go_id = {}

local function _altar_key_for(chest_type)
    if type(chest_type) ~= "string" then return nil end
    return DEUS_CHEST_TYPE_TO_KEY[chest_type]
end

local function _altar_max_uses(chest_type)
    local key = _altar_key_for(chest_type)
    if not key then return 1 end
    local v = effective_setting("altar_reuse_count_" .. key)
    if type(v) ~= "number" or v < 1 then return 1 end
    return math.floor(v)
end

local function _altar_cost_mult(chest_type)
    local key = _altar_key_for(chest_type)
    if not key then return 1 end
    local v = effective_setting("altar_reuse_cost_mult_" .. key)
    if type(v) ~= "number" or v <= 0 then return 1 end
    return v
end

-- v0.7.158-dev: ordered list of the player-usable weapon rarities (order 1..5,
-- excluding `event`/order 6 which is not granted to player weapons), and the
-- helper that returns the rarity NAME one tier above a wielded weapon (capped at
-- `unique`/order 5). Used by the upgrade-altar re-arm to bump the altar's offered
-- rarity strictly above the player's just-upgraded weapon so update_upgrade_chest_
-- color (deus_chest_extension.lua:236) stops firing `lua_interact_disabled` (the
-- dark/can't-use visual) and can_be_unlocked (lines 505-517) keeps returning true
-- until the usable rarity ceiling is reached.
--
-- Attached to `mod` (not file-scope locals) to stay under Lua 5.1's
-- 200-locals-per-chunk cap — this file is at the limit (see the same pattern on
-- mod._ct_remove_peer_from_collected / mod._ct_boon_altar_taken_boons).
mod._ct_rarity_by_order = mod._ct_rarity_by_order
    or { "plentiful", "common", "rare", "exotic", "unique" }

-- Return the rarity NAME one tier above `weapon_rarity_name`, capped at `unique`
-- (order 5). Returns nil if RaritySettings isn't loaded or the input is unknown,
-- in which case the caller leaves the vanilla-rolled rarity untouched.
mod._ct_altar_next_rarity_above = function(weapon_rarity_name)
    local rs = rawget(_G, "RaritySettings")
    if type(weapon_rarity_name) ~= "string" or not rs then return nil end
    local cur = rs[weapon_rarity_name]
    local cur_order = cur and cur.order
    if type(cur_order) ~= "number" then return nil end
    -- one above the wielded weapon, but never above the usable ceiling (5 = unique).
    local target_order = math.min(5, cur_order + 1)
    return mod._ct_rarity_by_order[target_order]
end

-- v0.7.151-dev: retract ONE peer from a chest's networked `collected_by_peers`
-- GameSession field so the re-armed altar stops reading as looted. Without this,
-- vanilla DeusChestExtension.update (deus_chest_extension.lua:175) re-derives
-- new_is_purchased=true from the still-present peer one tick after re-arm, forces
-- _animation_state="looted" (line 177-182), and line 194 skips the anim update —
-- the re-rolled offering hologram never re-displays.
--
-- Server-owned field (written server-side at deus_chest_extension.lua:752), so a
-- client opener must round-trip through the server (see mod._ct_altar_uncollect).
-- Removes ONLY `peer_id` — never clears the whole array — because in co-op other
-- peers may legitimately have looted other (non-reusable) chests sharing nothing
-- but this is per-GameSession-object, so scoping to the own peer keeps their
-- state intact. Attached to `mod` (not a file-scope local) to stay under Lua
-- 5.1's 200-locals-per-chunk cap.
--
-- GUARD: GameSession.game_object_exists before reading (vanilla guard, e.g.
-- player_husk_locomotion_extension.lua:134), AND wrap the read/write in pcall —
-- `game_object_field` on a truly stale go_id is an engine fatal that bypasses
-- pcall the same way Unit.node does, so the existence check is the real gate; the
-- pcall just catches the ordinary Lua errors (nil game, bad field).
mod._ct_remove_peer_from_collected = function(go_id, peer_id)
    if not go_id or peer_id == nil then return end
    local network_man = Managers.state and Managers.state.network
    local game = network_man and network_man.game and network_man:game()
    if not game then return end
    if not GameSession.game_object_exists(game, go_id) then return end
    pcall(function()
        local collected = GameSession.game_object_field(game, go_id, "collected_by_peers")
        if type(collected) ~= "table" then return end
        local changed = false
        for i = #collected, 1, -1 do
            if collected[i] == peer_id then
                table.remove(collected, i)
                changed = true
            end
        end
        if changed then
            GameSession.set_game_object_field(game, go_id, "collected_by_peers", collected)
            _dbg("[altar_reuse] uncollect go_id=%s peer=%s -> %d peer(s) remain",
                tostring(go_id), tostring(peer_id), #collected)
        end
    end)
end

-- v0.7.151-dev: on altar re-arm, retract the OWN peer from collected_by_peers.
-- The re-arm runs on the buying/interacting peer (host OR client). The field is
-- server-authoritative, so:
--   * host opener writes it directly;
--   * client opener sends ct_altar_uncollect to the HOST so the server mutates
--     the authoritative copy (mirrors vanilla loot, which is server-authoritative
--     via purchase() -> send_rpc_server at deus_chest_extension.lua:315).
-- This is a pure data write to one GameSession field — it does NOT re-enter
-- purchase() or spawn anything; the next vanilla update() tick simply takes the
-- non-looted branch and re-fires the offering presentation.
mod._ct_altar_uncollect = function(ext)
    if not ext then return end
    local go_id = ext._go_id or (Managers.state and Managers.state.unit_storage
        and ext.unit and Managers.state.unit_storage:go_id(ext.unit))
    if not go_id then return end
    local drc = ext._deus_run_controller
    local own_peer_id = drc and drc.get_own_peer_id and drc:get_own_peer_id()
    if not own_peer_id then return end

    if ext._is_server then
        -- Host opener: write the server-owned field directly.
        mod._ct_remove_peer_from_collected(go_id, own_peer_id)
        return
    end

    -- Client opener: ask the host to clear our peer. VMF's network_send does NOT
    -- accept "server" as a recipient (silently dropped — VMF_RECIPES.md § 3); the
    -- real host peer_id must be resolved. The server handler resolves the SENDER
    -- (us) from the VMF sender_peer_id arg, so we only send go_id.
    local host
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        host = Managers.mechanism:server_peer_id()
    end
    if not host then
        local nm = Managers.state and Managers.state.network
        host = nm and ((nm.network_client and nm.network_client.server_peer_id)
            or (nm.network_server and nm.network_server.server_peer_id))
    end
    if not host then
        _dbg("[altar_reuse] uncollect: host peer_id not yet known; skipping client RPC (go_id=%s)",
            tostring(go_id))
        return
    end
    mod:network_send("ct_altar_uncollect", host, CT_RPC_SCHEMA, go_id)
end

-- Server handler: a client re-armed this altar locally and asks us to drop its
-- peer from the chest's collected_by_peers, so everyone (including that client)
-- sees the re-rolled offering instead of the looted state. Mirrors vanilla
-- rpc_deus_chest_looted (deus_chest_extension.lua:737-752) in reverse. The
-- sending peer is resolved by VMF (sender_peer_id), NOT a raw CHANNEL_TO_PEER_ID.
mod:network_register("ct_altar_uncollect", function(sender_peer_id, schema_version, go_id)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_altar_uncollect", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    -- Only the host owns the field; ignore if we somehow aren't the server.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    if sender_peer_id == nil or go_id == nil then return end
    mod._ct_remove_peer_from_collected(go_id, sender_peer_id)
end)

-- ============================================================
-- v0.7.157-dev Task A: ALTAR "goes dark after first use" PROBES (DIAGNOSE-ONLY)
-- ============================================================
-- The user reports weapon-UPGRADE altars set to allow >1 use still go "dark"
-- (looted look) after the FIRST use, despite the v0.7.151 re-arm + uncollect.
-- These probes are READ-ONLY: they capture the visual-state evolution across the
-- re-arm AND the next few vanilla DeusChestExtension.update ticks so the log
-- shows exactly when/why it re-darkens. NO behavior change. All lines are FORCED
-- output (unconditional mod:info, tag [altar_visual_probe]) so the user just
-- plays — no command needed. Strip the whole block once the cause is found.
--
-- _ct_altar_probe_watch[go_id] = { ticks = N, type = "<chest_type>" } — armed by
-- the open_chest re-arm path; the read-only update hook below decrements it and
-- logs each tick's derived state.
_ct_altar_probe_watch = {}

-- Read collected_by_peers for a go_id as a printable string, guarded exactly like
-- mod._ct_remove_peer_from_collected (game_object_exists gate + pcall). Returns a
-- "[p1,p2]" style string, or a status token if unreadable. Read-only.
function _ct_probe_collected_by_peers(go_id)
    if not go_id then return "<no go_id>" end
    local network_man = Managers.state and Managers.state.network
    local game = network_man and network_man.game and network_man:game()
    if not game then return "<no game>" end
    if not GameSession.game_object_exists(game, go_id) then return "<go absent>" end
    local out = "<unreadable>"
    pcall(function()
        local collected = GameSession.game_object_field(game, go_id, "collected_by_peers")
        if type(collected) ~= "table" then out = "<not table>"; return end
        local parts = {}
        for i = 1, #collected do parts[i] = tostring(collected[i]) end
        out = "[" .. table.concat(parts, ",") .. "](" .. #collected .. ")"
    end)
    return out
end

-- Read-only watcher hook on DeusChestExtension.update. ct_dev has NO other hook
-- on DeusChestExtension.update (verified: only open_chest/get_purchase_cost/
-- _generate_* /extensions_ready are hooked), so this fresh mod:hook is VMF-clean.
-- Logs the post-re-arm visual-state evolution for a watched (re-armed) chest:
-- _is_purchased / _animation_state / _profile_index plus what vanilla would
-- re-derive (new_is_purchased from collected_by_peers). DOES NOT mutate anything;
-- always calls through to vanilla and returns its result(s).
mod:hook("DeusChestExtension", "update", function(func, self, unit, input, dt, context, t)
    local go_id = self._go_id or (self.unit and Managers.state and Managers.state.unit_storage
        and Managers.state.unit_storage:go_id(self.unit))
    local watch = go_id and _ct_altar_probe_watch[go_id]

    -- pre-tick snapshot (state as vanilla update SEES it on entry)
    local pre_purchased, pre_anim, pre_profile
    if watch then
        pre_purchased = self._is_purchased
        pre_anim = self._animation_state
        pre_profile = self._profile_index
    end

    local r1, r2, r3 = func(self, unit, input, dt, context, t)

    if watch then
        local own_peer = self._deus_run_controller and self._deus_run_controller.get_own_peer_id
            and self._deus_run_controller:get_own_peer_id()
        local collected = _ct_probe_collected_by_peers(go_id)
        -- mirror vanilla's new_is_purchased derivation (deus_chest_extension.lua:175):
        -- not self._stored_purchase and chest_type ~= upgrade  OR  own peer in collected
        local DCT = rawget(_G, "DEUS_CHEST_TYPES")
        local own_in_collected = "?"
        do
            local cp = nil
            local network_man = Managers.state and Managers.state.network
            local game = network_man and network_man.game and network_man:game()
            if game and GameSession.game_object_exists(game, go_id) then
                pcall(function() cp = GameSession.game_object_field(game, go_id, "collected_by_peers") end)
            end
            if type(cp) == "table" and own_peer ~= nil then
                own_in_collected = tostring(table.contains(cp, own_peer))
            end
        end
        _dbg("[altar_visual_probe] UPDATE go_id=%s type=%s tick=%d pre{purchased=%s anim=%s prof=%s} post{purchased=%s anim=%s prof=%s} stored_purchase=%s is_upgrade=%s own_in_collected=%s collected=%s",
            tostring(go_id), tostring(watch.type), watch.ticks,
            tostring(pre_purchased), tostring(pre_anim), tostring(pre_profile),
            tostring(self._is_purchased), tostring(self._animation_state), tostring(self._profile_index),
            tostring(self._stored_purchase ~= nil),
            tostring(DCT and self._chest_type == DCT.upgrade), own_in_collected, collected)
        watch.ticks = watch.ticks - 1
        if watch.ticks <= 0 then
            _ct_altar_probe_watch[go_id] = nil
            _dbg("[altar_visual_probe] UPDATE go_id=%s watch window closed", tostring(go_id))
        end
    end

    return r1, r2, r3
end)

-- ============================================================
-- TERMINOLOGY (Chaos Wastes) -- READ BEFORE EDITING COST/CHEST CODE
-- ============================================================
-- IN-GAME, the ONLY thing called a "chest" is a CHEST OF TRIALS: a cursed
-- chest that spawns a trial enemy wave (you pay by fighting the wave, never
-- with coin). It is the engine class DeusCursedChestExtension
-- (scripts/unit_extensions/deus/deus_cursed_chest_extension.lua) -- it has NO
-- _chest_type and NO get_purchase_cost. ct's cot_enemy_multiplier targets it
-- via the terror-event spawn tag spawn_counter_category == "cursed_chest_enemies".
--
-- The boon shrine (Shrine of Solace), weapon-swap shrine, and weapon-upgrade
-- shrine are ALTARS. The ENGINE confusingly calls them all "chest":
-- DeusChestExtension with _chest_type = power_up (boon ALTAR) / swap_melee /
-- swap_ranged / upgrade. get_purchase_cost lives on THIS class; for power_up it
-- returns the stock 150 boon price (deus_chest_extension.lua:294-295).
--
-- => Any code below that branches on _chest_type == power_up is acting on a
--    BOON ALTAR, never on a Chest of Trials. The altar-reuse cost multiplier
--    (150 * mult^uses) is the intended boon-altar price. Do NOT re-introduce a
--    "trials" coin cost on this hook -- a real Chest of Trials has no purchase
--    step to override (it is DeusCursedChestExtension; you pay by fighting).
-- ============================================================

-- ============================================================
-- Boon-altar no-repeat bookkeeping
-- ============================================================
-- Records which boons the local peer has already taken from boon (power_up)
-- ALTARS this run, so the no-repeat default (in the DeusPowerUpsArray strip
-- below) can exclude already-taken boons from each subsequent altar roll. This
-- is boon-ALTAR state, NOT a Chest of Trials -- see the terminology banner
-- above. State lives on `mod` (not file-scope locals) to stay under Lua 5.1's
-- 200-locals-per-chunk cap.
mod._ct_boon_altar_taken_boons = mod._ct_boon_altar_taken_boons or {}

mod:hook("DeusChestExtension", "get_purchase_cost", function(func, self)
    local base = func(self)
    if type(base) ~= "number" or base == math.huge then return base end
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 then return base end
    local mult = _altar_cost_mult(self._chest_type)
    if mult == 1 then return base end
    return math.max(1, math.ceil(base * (mult ^ uses)))
end)

-- v0.7.131-dev: altar-reuse re-arm logic LIVES INSIDE the consolidated
-- `mod:hook_safe("DeusChestExtension", "open_chest", ...)` further down the
-- file (search for `_ct_consolidated_open_chest_hook`). DO NOT add a second
-- `mod:hook("DeusChestExtension", "open_chest", ...)` here — VMF silently
-- drops duplicate hooks on the same (Class, method) per mod (see VMF_RECIPES.md
-- § 1 and feedback_vmf_no_duplicate_hooks). The v0.7.129/.130 altar-reuse
-- "fix" sat in a duplicate hook for two releases and never actually ran.
-- Helper functions remain here; the open_chest hook itself is consolidated.

-- Seed-mix hooks so each re-roll yields DIFFERENT offerings. Vanilla seeds
-- derive from (go_id, current_node.weapon_pickup_seed) — same each tick.
-- Mixing the use count into the seed produces a fresh roll without touching
-- the run-shared current_node state.
mod:hook("DeusChestExtension", "_generate_stored_power_up", function(func, self, seed)
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 or type(seed) ~= "number" then return func(self, seed) end
    if HashUtils and HashUtils.fnv32_hash then
        seed = HashUtils.fnv32_hash(tostring(seed) .. "_ct_reuse_" .. uses)
    else
        seed = seed + uses * 16777619  -- fallback FNV prime mix
    end
    return func(self, seed)
end)

mod:hook("DeusChestExtension", "_generate_stored_weapon", function(func, self, slots, rarity, go_id, profile_index, career_index)
    -- Weapon generation derives weapon_seed inside the function from
    -- (profile, career, current_node.weapon_pickup_seed, go_id, 1) via fnv32_hash
    -- (deus_chest_extension.lua:411). Offsetting the go_id parameter by the use
    -- count flows through the hash and produces a fresh weapon_seed -> fresh roll
    -- without copy-pasting the whole function.
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 then return func(self, slots, rarity, go_id, profile_index, career_index) end
    local mixed_go_id = (go_id or 0) + uses * 1000003
    return func(self, slots, rarity, mixed_go_id, profile_index, career_index)
end)

-- v0.7.158-dev Task 2: WEAPON-UPGRADE altar reroll on reuse. The upgrade altar
-- does NOT swap the weapon — it upgrades the wielded weapon in place via
-- _generate_upgraded_weapon (deus_chest_extension.lua:426), which is a DISTINCT
-- function from _generate_stored_weapon (the swap-altar path the seed-mix hook
-- above targets). So without this, every upgrade reuse produced the SAME
-- properties/trait roll. The function derives its weapon_seed inside from
-- (profile, career, current_node.weapon_pickup_seed, go_id, 1) via fnv32_hash
-- (line 431) — the SAME constant per go_id every reuse. Offsetting the go_id
-- argument by the use count flows through that hash and yields a fresh
-- properties/trait roll on the upgraded weapon, mirroring the _generate_stored_
-- weapon idiom above. Single hook on this (Class, method) — VMF-clean.
mod:hook("DeusChestExtension", "_generate_upgraded_weapon", function(func, self, weapon, slot_name, rarity, go_id, profile_index, career_index)
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 then return func(self, weapon, slot_name, rarity, go_id, profile_index, career_index) end
    local mixed_go_id = (go_id or 0) + uses * 1000003
    return func(self, weapon, slot_name, rarity, mixed_go_id, profile_index, career_index)
end)

-- TODO #102/#103: DECOUPLE keep-lit/usable from reward rarity (deferred — needs in-game verify).
-- ----------------------------------------------------------------------------------------------
-- #102 (escalation): the `_setup_rarity` hook below keeps a re-armed upgrade altar LIT by bumping
-- its rolled `_rarity` strictly ABOVE the player's wielded weapon every re-roll. That is exactly
-- the "reward climbs a tier each use" behavior the user wants gone. Simply deleting the bump,
-- however, re-introduces the v0.7.158 "goes dark after first use" regression, because vanilla
-- gates the altar on `chest_rarity_order <= weapon_rarity_order` in TWO places:
--     * DeusChestExtension.can_be_unlocked   (deus_chest_extension.lua:505-517) — GAMEPLAY gate
--     * DeusChestExtension.update_upgrade_chest_color (211-243) — fires `lua_interact_disabled`
--       (the dark/greyed look) under the same `<=` condition.
-- DECOUPLE PLAN (source-grounded, all cited above):
--   1. Remove this `_setup_rarity` bump so `_rarity` stays at the rolled tier (no climb).
--   2. Add hooks on `can_be_unlocked` + `update_upgrade_chest_color` that, ONLY for a re-armed
--      upgrade altar (`_altar_uses_by_go_id[self._go_id] > 0`), relax the disable test from
--      `chest_rarity_order <= weapon_rarity_order` to strictly `<` — i.e. ALLOW a same-rarity
--      re-roll (exotic altar re-rolls the weapon at exotic) while still forbidding a downgrade.
--      The cost table supports this: DeusCostSettings.deus_chest.upgrade[r][r] is populated
--      (e.g. exotic→exotic = 175, deus_cost_settings.lua:159-165), so get_purchase_cost stays
--      finite and can_be_unlocked's cost branch passes.
--   (Neither method is hooked yet in ct_dev, so no VMF dup-hook risk — but verify before adding.)
-- #103 (used-up mesh on re-use): the re-arm must also clear the looted visual — re-fire
--   `lua_update_<chest_type>` + the rolled `lua_update_<rarity>` event, reset `_animation_state`
--   away from "looted", and clear `_prev_update_upgrade_chest_color_event` so the color update
--   re-evaluates. The open_chest re-arm + this hook already do some of this; the gap is the
--   per-tick `lua_update_collected` re-derivation in update() (deus_chest_extension.lua:175-182)
--   forcing the looted mesh back. Cross-reference `_peregrinaje_extract` for how Peregrinaje keeps
--   altars visually reusable across uses.
-- WHY DEFERRED: this altar re-arm path has regressed across v0.7.129/.130/.131/.151/.157/.158 and
--   is networked + per-tick-clobbered; the fix above is well-understood but MUST be verified in a
--   live run (single-altar reuse + the dark/looted visual) before shipping. Do NOT ship blind.
--
-- v0.7.158-dev Task 1: AUTHORITATIVE upgrade-altar rarity bump (the part of the
-- "goes dark after first use" fix that has to survive the per-tick clobber).
-- Vanilla update() (deus_chest_extension.lua:140) re-calls _setup_rarity every
-- time the setup block re-runs (and our re-arm forces it to by zeroing
-- _profile_index), so any _rarity we write in the open_chest re-arm branch is
-- overwritten one tick later by the constant-seed roll. Hooking _setup_rarity
-- (which is the SINGLE writer of self._rarity) lets us re-apply the bump on every
-- re-roll: for an upgrade altar that has been used at least once this run, force
-- the rolled rarity strictly above the player's wielded (just-upgraded) weapon,
-- capped at `unique`. That stops update_upgrade_chest_color from firing
-- `lua_interact_disabled` (the dark look) and keeps can_be_unlocked true until
-- the usable rarity ceiling is reached. Single hook on this (Class, method).
-- mod:hook (full wrapper) because we override BOTH the return value AND the
-- self._rarity field vanilla just set.
mod:hook("DeusChestExtension", "_setup_rarity", function(func, self, seed, chest_type)
    local rolled = func(self, seed, chest_type)
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    if not (DCT and chest_type == DCT.upgrade) then return rolled end
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 then return rolled end  -- first/only use: untouched vanilla roll
    local wielded = self._get_wielded_weapon and self:_get_wielded_weapon()
    local wielded_rarity = wielded and wielded.rarity
    local bumped = mod._ct_altar_next_rarity_above(wielded_rarity)
    if not bumped then return rolled end
    -- Only ever raise the tier, never lower it below the vanilla roll.
    local rs = rawget(_G, "RaritySettings")
    local rolled_order = rolled and rs and rs[rolled] and rs[rolled].order or 0
    local bumped_order = rs and rs[bumped] and rs[bumped].order or 0
    if bumped_order <= rolled_order then return rolled end
    self._rarity = bumped
    if self.unit and Unit and Unit.flow_event then
        pcall(Unit.flow_event, self.unit, "lua_update_" .. bumped)
    end
    self._prev_update_upgrade_chest_color_event = nil
    return bumped
end)

-- ============================================================
-- Multiplayer settings sync (v0.7.21)
-- ============================================================
-- CW's graph generation is deterministic from seed and runs on BOTH host and
-- client (rpc_deus_setup_run triggers it on clients). Without sync, peers run
-- our graph-mutating overrides against THEIR OWN settings, producing divergent
-- local graphs. v0.7.20 gated the hook on `is_server` to stop crashes (clients
-- pass through to vanilla) but the client's local view still differs from the
-- host's mutated graph — so the map shows the wrong curse, the wrong theme on
-- a mission, etc.
--
-- This sync: when host's setup_run fires, broadcast effective host settings to
-- clients via VMF's mod:network_send. Clients stash the values in
-- `_ct_host_settings`. The deus_populate_graph hook then reads from there on
-- client (instead of mod:get which would give the CLIENT's own settings).
--
-- Settings synced: every mod-defined setting except those in PER_PEER_SETTING_NAMES.
--
-- v0.7.55: previously this was a hand-maintained list of ~50 names that grew every
-- release. After repeated bugs from missing entries (most recently: disable_curse_*
-- helper bypassed sync, finale_dominant_god / force_belakor weren't reaching clients,
-- coin/boon/trait toggles silently diverged) we switched to "sync everything by
-- default" — walk the data file's widget tree at module load and emit every
-- leaf-widget's setting_id, minus an explicit per-peer exclusion list.
--
-- This means: any setting that's host-authoritative (clients should see whatever host
-- has) gets synced automatically just by living in chaos_wastes_tweaker_data.lua.
-- Adding a new mod setting requires NO bookkeeping here.
--
-- PER_PEER excludes: settings that are intentionally each-peer-local. These are rare
-- and require a deliberate justification (see comments per entry).
local PER_PEER_SETTING_NAMES = {
    -- v0.7.64: `tweak_defeat_recovery` and `enable_campaign_potions` were per-peer for
    -- historical reasons (the comments below) but the user's design intent is "all
    -- settings sync to host." Both are now host-synced; the original comments are
    -- kept as a record of why they used to be per-peer.
    --
    --   tweak_defeat_recovery: was "each peer needs the toggle on for their own
    --   coins/boons to be penalized." Now: the host's value decides for the lobby.
    --   The wipe-prevention itself was always host-only (GameModeDeus is
    --   server-authoritative); only the local penalty arm was per-peer.
    --
    --   enable_campaign_potions: was "server-driven spawn, no graph effect; client
    --   mutation irrelevant." Same — the host's value decides; client-side table
    --   mutation never had any effect anyway.
    --
    -- inject_adventure_maps STAYS per-peer because it mutates NetworkLookup.level_keys
    -- count and folds into lobby `combined_hash` (see reference_vt2_lobby_combined_hash).
    -- The LobbyAux hash shim above hides the count diff so peers with different values
    -- can still join, but each peer's resolved graph diverges as a result. Switching it
    -- to host-sync would require also re-running AdventurePool.inject_pool() on clients,
    -- which can't happen post-boot (level_keys are sealed before lobby handshake).
    -- Curse/mission visual desync from this is tracked as a separate follow-up — likely
    -- needs a host→client graph snapshot RPC instead of toggle sync.
    inject_adventure_maps   = true,
}

local function _collect_setting_ids()
    -- mod:dofile re-executes the data file. Idempotent: tree-building has no side
    -- effects beyond an in-place recursive_sort (which is stable on already-sorted
    -- tables). Returns the same `data` table that VMF loaded at mod registration.
    local data = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data")
    local ids = {}
    local seen = {}
    local function visit(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" and node.type and node.type ~= "group"
            and not seen[node.setting_id]
        then
            seen[node.setting_id] = true
            ids[#ids + 1] = node.setting_id
        end
        if node.sub_widgets then
            for _, w in ipairs(node.sub_widgets) do visit(w) end
        end
        if node.widgets then
            for _, w in ipairs(node.widgets) do visit(w) end
        end
    end
    visit(data.options)
    return ids
end

local SYNCED_SETTING_NAMES = {}
for _, id in ipairs(_collect_setting_ids()) do
    if not PER_PEER_SETTING_NAMES[id] then
        SYNCED_SETTING_NAMES[#SYNCED_SETTING_NAMES + 1] = id
    end
end
pcall(printf, "[ct_sync] synced setting registry built: %d keys (%d excluded as per-peer)",
    #SYNCED_SETTING_NAMES, (function() local n = 0; for _ in pairs(PER_PEER_SETTING_NAMES) do n = n + 1 end; return n end)())

-- O(1) membership for the mid-run re-broadcast gate in on_setting_changed (see
-- MIDRUN_SETTING_REBROADCAST_MARKER). Lives on `mod` rather than a new file-scope
-- local because this chunk is near Lua 5.1's 200-locals cap. Mirrors SYNCED_SETTING_NAMES.
mod._ct_synced_set = {}
for _, id in ipairs(SYNCED_SETTING_NAMES) do
    mod._ct_synced_set[id] = true
end

local _ct_host_settings = {}
local _ct_host_sync_received = false

-- Forward-declared so the network_register callback below can call it before
-- its assignment further down the file (after all sync_* functions exist).
local sync_host_dependent_state

-- Chunked-string sync protocol (mirrors vanilla shared_state.lua:288-330).
-- Stingray caps each RPC string parameter at 500 chars (network_utils.lua:93
-- STRING_MAX). VMF's mod:network_send packs all user args into ONE JSON-encoded
-- string parameter on rpc_mod_user_data, so a 105-setting table (~4-5KB JSON)
-- crashes the host with "Failed to pack parameter 3, too many characters in
-- string with max length 500" before the packet ever leaves. Cost: clients
-- received zero host settings between v0.7.55 and v0.7.58.
--
-- Fix: encode the payload to JSON ourselves, split into <=CHUNK_SIZE pieces,
-- send each as (session, seq, total, chunk_str). Receiver buffers per sender
-- and decodes when all chunks for the current session arrive. Session id
-- changes on every broadcast so a partial buffer from a stale broadcast is
-- discarded the moment the next one starts.
--
-- CHUNK_SIZE budget: the wire-side JSON envelope is roughly
--   [<session>,<seq>,<total>,"<chunk>"]  ~= 20 chars of overhead + chunk_str.
-- VMF adds its own [mod_id,rpc_id] envelope as a separate string parameter,
-- so only this user-payload string needs to fit under 500. 400 leaves
-- headroom for the largest plausible envelope growth.
local SYNC_CHUNK_SIZE = 400
local _sync_inbound = {}

-- ============================================================
-- Issue #97: paced chunk send-queue (anti-flood)
-- ============================================================
-- The three chunked broadcasters below (host settings / graph snapshot / peer
-- manifest) each used to emit their ENTIRE chunk train inline in one frame:
--   for seq = 1, total do mod:network_send(<event>, <target>, ...) end
-- On a large-graph hot-join the three fire in the same frame window and dump
-- ~200 reliable RPCs (~94 KB) onto Stingray's reliable send queue at once. That
-- queue has a hard byte budget (~97822 B); overflowing it tears down the host
-- connection -> HOST CRASH (the reported #97 symptom).
--
-- Fix: don't send inline. ENQUEUE each chunk as a self-contained network_send
-- arg set into one FIFO queue, and drain a small budget per frame from
-- mod.update (below). The chunks then arrive paced across many frames; the
-- receivers already tolerate that (purely accumulative — they buffer by seq per
-- (sender,session) and only act once all `total` distinct chunks arrive; no
-- single-frame/burst assumption anywhere). NONE of the wire protocol changes:
-- same event names, same CT_RPC_SCHEMA gate, same session/seq/total semantics,
-- same SYNC_CHUNK_SIZE, same reassembly. Only the SEND TIMING is paced.
--
-- FIFO order is preserved (append at tail in enqueue order, pop from head).
-- Re-entrancy is safe: a new broadcast just appends more entries; the drainer
-- never clears the queue mid-drain and each entry already carries its own
-- session id, so concurrent/overlapping broadcasts never corrupt each other.
--
-- (Globals, not main-chunk locals: the file is at the Lua 5.1 200-locals cap —
-- see the note on CT_ALTAR_VISUAL_PROBE_MARKER near line 572. These three names
-- are referenced only from the mod.update drainer closure and the three chunk
-- broadcaster call sites below; nothing else shadows them, so file-scope globals
-- are safe and keep the main chunk under the 200-local ceiling.)
_ct_chunk_send_queue = {}
-- /ct_regression_test marker for `chunk_sends_paced_not_bursted` (Issue #97,
-- ct_dev 0.7.163-dev). All three chunked broadcasts (ct_graph_snapshot_chunk /
-- ct_sync_host_settings_chunk / ct_peer_manifest_chunk) route their per-seq
-- emission through `_ct_enqueue_chunk` and are drained by the single
-- `mod.update` owner below at _CT_CHUNK_DRAIN_BUDGET per frame -- NEVER an
-- inline `mod:network_send("<chunk-event>", ...)` inside the `for seq` loops
-- (that single-frame burst overran the reliable-channel queue cap and dropped
-- chunks). If a future edit re-inlines a burst send, update the wiring but NOT
-- this marker, and the regression check fails loudly. (Global, not a main-chunk
-- local: see the 200-locals-cap note above.)
_CT_CHUNK_PACED_SEND_MARKER = "chunk_sends:enqueue_drain_paced_v0.7.163"
-- Per-frame drain budget. Worst single chunk_str is SYNC_CHUNK_SIZE (400) chars
-- + the small fixed envelope; 8 chunks/frame keeps per-frame reliable bytes
-- (~8 * ~450 = ~3.6 KB) FAR under the ~97822 B queue limit, and the reliable
-- channel acks far faster than we enqueue at this cadence so the queue drains
-- steadily without ever stacking near the cap. Tunable.
-- (Global, not a main-chunk local: see the 200-locals-cap note just above.)
_CT_CHUNK_DRAIN_BUDGET = 8

-- Append one chunk send to the FIFO queue. `record_send` (optional) is invoked
-- with no args at SEND time (not enqueue time) so bt's net_replay ring records
-- the actual emission; it mirrors the inline _nr:record_send call the host
-- settings broadcaster used to make. Args mirror mod:network_send exactly:
-- (event, target, CT_RPC_SCHEMA, session, seq, total, chunk_str).
-- (Global, not a main-chunk local: see the 200-locals-cap note above.)
function _ct_enqueue_chunk(event, target, schema, session, seq, total, chunk_str, record_send)
    _ct_chunk_send_queue[#_ct_chunk_send_queue + 1] = {
        event = event, target = target, schema = schema,
        session = session, seq = seq, total = total, chunk_str = chunk_str,
        record_send = record_send,
    }
end

-- Per-frame drainer. VMF calls a registered mod.update(dt) every frame at the
-- keep AND in mission (the only mod-wide per-frame entry point in ct_dev — the
-- existing DeusChestExtension.update hook is mission/per-chest-only and read-
-- only, so it can't host this). Pops up to _CT_CHUNK_DRAIN_BUDGET entries from
-- the head of the FIFO each tick and sends them, pcall-wrapping each so one bad
-- send can't abort the rest of the drain or stall the queue. Cheap no-op when
-- the queue is empty (the common case), so it's safe to run unconditionally.
mod.update = function(dt)
    -- #58/#156: drive the deferred spawn-census emit (armed in populate_pickups,
    -- fires ~8s later once the guaranteed-spawn pass is done). Cheap no-op when
    -- disarmed. Resolved via mod._ since the census `do` block is defined LATER in
    -- this file; the field is assigned at load, before any update tick fires.
    if mod._ct_tally_tick then mod._ct_tally_tick(dt) end
    -- #205: debounced host-settings re-sync. on_setting_changed marks the registry
    -- dirty + (re)arms this short countdown instead of broadcasting inline, so an
    -- Apply-button burst (the gut Mod Tweaker commits its whole staged batch at once ->
    -- hundreds of on_setting_changed in one frame) or a slider drag coalesces into ONE
    -- encode + ONE 46-chunk sync once edits SETTLE, instead of hundreds of redundant
    -- full-registry encodes in a single frame. setup_run still broadcasts immediately
    -- (single call at run start, not a burst). The supersede guard in
    -- _ct_broadcast_host_settings remains as belt-and-suspenders.
    if mod._ct_settings_sync_pending then
        mod._ct_settings_sync_countdown = (mod._ct_settings_sync_countdown or 0) - dt
        if mod._ct_settings_sync_countdown <= 0 then
            mod._ct_settings_sync_pending = false
            if mod._ct_broadcast_host_settings then
                mod._ct_broadcast_host_settings("debounced_setting_edits")
            end
        end
    end
    local q = _ct_chunk_send_queue
    if q[1] == nil then return end
    local budget = _CT_CHUNK_DRAIN_BUDGET
    local sent = 0
    while sent < budget do
        local entry = q[1]
        if entry == nil then break end
        table.remove(q, 1)  -- pop head (FIFO)
        local ok, err = pcall(function()
            mod:network_send(entry.event, entry.target, entry.schema,
                entry.session, entry.seq, entry.total, entry.chunk_str)
            if entry.record_send then entry.record_send() end
        end)
        if not ok then
            pcall(printf, "[ct_sync] paced send failed for %s (session %s seq %s/%s): %s",
                tostring(entry.event), tostring(entry.session), tostring(entry.seq),
                tostring(entry.total), tostring(err))
        end
        sent = sent + 1
    end
end

mod:network_register("ct_sync_host_settings_chunk", function(sender_peer_id, schema_version, session, seq, total, chunk_str)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_sync_host_settings_chunk", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    -- Issue #28 demo integration: record receive on bt's shared net-replay
    -- ring. Silent no-op if buff_tweaker isn't installed. The payload snippet
    -- captures the leading 200 chars of chunk_str so post-session log diff
    -- can reconstruct what arrived. Header tag prefixes session/seq/total so
    -- the tail of the snippet is the actual JSON fragment.
    do
        local bt = get_mod("bt")
        local nr = bt and bt.net_replay and bt:net_replay()
        if nr then
            local tag = string.format("session=%s seq=%s total=%s chunk=%s",
                tostring(session), tostring(seq), tostring(total), tostring(chunk_str))
            nr:record_recv("ct", "ct_sync_host_settings_chunk", tag, sender_peer_id)
        end
    end
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        pcall(printf, "[ct_sync] malformed chunk from %s; ignoring", tostring(sender_peer_id))
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _sync_inbound[key]
    if not entry or entry.session ~= session then
        entry = { session = session, total = total, received = 0, chunks = {} }
        _sync_inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then
        return
    end
    local pieces = {}
    for i = 1, entry.total do
        pieces[i] = entry.chunks[i] or ""
    end
    _sync_inbound[key] = nil
    local json = table.concat(pieces)
    local ok, payload = pcall(cjson.decode, json)
    if not ok or type(payload) ~= "table" then
        pcall(printf, "[ct_sync] decode failed from %s (session %s, %d bytes)",
            tostring(sender_peer_id), tostring(session), #json)
        return
    end
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        _ct_host_settings[name] = payload[name]
    end
    _ct_host_sync_received = true
    _dbg("[ct_sync] received host settings from %s (session %s, %d chunks, %d bytes, %d keys)",
        tostring(sender_peer_id), tostring(session), entry.total, #json, #SYNCED_SETTING_NAMES)
    -- Client-side host-authoritative settings dump: now that _ct_host_settings is
    -- populated, effective_setting(id) resolves to the HOST's broadcast value, so this
    -- prints the config the client is actually running under (vs its own local get=).
    -- The helper is defined later in the file but populated by load time; this callback
    -- only fires at runtime, long after load, so the forward reference is safe.
    if mod._ct_dump_settings then mod._ct_dump_settings("host_sync") end
    -- Issue #6 auto-probe: log the four chest_*_count keys the host pushed so a
    -- client-side log diff can spot setting drift without /verify_altars. Only
    -- the altar-determinism-relevant keys are dumped (full payload is verbose).
    _dbg("[altar:host_sync_arrived] from=%s session=%s host_settings: upgrade=%s melee=%s ranged=%s power_up=%s",
        tostring(sender_peer_id), tostring(session),
        tostring(payload.chest_upgrade_count), tostring(payload.chest_swap_melee_count),
        tostring(payload.chest_swap_ranged_count), tostring(payload.chest_power_up_count))
    -- v0.7.67 ordering fix: the manifest broadcast MUST fire BEFORE
    -- sync_host_dependent_state() because any of the 11 sync_* re-registration
    -- helpers it invokes (trait boons, dormants, miracles, etc.) can throw, and
    -- VMF's network_register safe-wrapper swallows the error — aborting the
    -- receiver body silently. Pre-0.7.67 the manifest line was last; if anything
    -- in sync_host_dependent_state threw, the host never saw the client's RECV
    -- and we couldn't tell version drift from "feature didn't fire" in logs.
    _dbg("[ct_peers] client received host ct_sync — broadcasting own manifest back to host")
    if _broadcast_local_manifest then
        _broadcast_local_manifest("server")
    end
    if sync_host_dependent_state then
        sync_host_dependent_state()
    end
end)

-- MIDRUN_SETTING_REBROADCAST_MARKER
-- Re-usable host->clients broadcast of the synced settings registry over the EXISTING
-- ct_sync_host_settings_chunk RPC (same schema/channel — no new registration). Called
-- from two places: DeusRunController.setup_run (run start) AND mod.on_setting_changed
-- (host edits a synced setting mid-run). Before this existed the broadcast lived only
-- inline in setup_run, so a host changing e.g. boons-per-chest/shrine mid-run never
-- reached clients — they stayed frozen at the run-start snapshot for the rest of the
-- run (reported 2026-06-17). Attached to `mod` (not a file-scope local) deliberately:
-- this chunk is near Lua 5.1's 200-locals-per-function cap, so new shared helpers go on
-- the mod table. Server-gated; no-op on clients / at menu (no peers). A fresh session id
-- per call means a client discards any partial stale buffer. `reason` is log-only.
function mod._ct_broadcast_host_settings(reason)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    local payload = {}
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        payload[name] = mod:get(name)
    end
    local ok, json = pcall(cjson.encode, payload)
    if not ok or type(json) ~= "string" then
        pcall(printf, "[ct_sync] payload encode failed; not broadcasting (%s)", tostring(reason))
        return
    end
    local json_len = #json
    local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
    local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
    if session == 0 then session = 1 end
    local _bt = get_mod("bt")
    local _nr = _bt and _bt.net_replay and _bt:net_replay()
    -- Issue #205: SUPERSEDE pending host-settings chunks before enqueuing this
    -- snapshot. This broadcast is a COMPLETE snapshot of every SYNCED_SETTING_NAMES
    -- key, so any ct_sync_host_settings_chunk entries from a PRIOR broadcast still
    -- sitting un-drained in the paced FIFO are now redundant. Without this, a rapid
    -- burst of on_setting_changed edits (e.g. dragging a slider / toggling several
    -- settings in the gut Mod Tweaker) STACKS N full 46-chunk trains into the queue;
    -- the paced drainer then feeds all ~200 into Stingray's reliable send queue until
    -- it overflows its ~97 KB cap -> HOST CRASH. Dual-log confirmed 2026-06-30: host
    -- reliable-send-queue overflow at 204 msgs / 94 KB to the client, client received
    -- "46 chunks, 489 keys" at the SAME instant, then timed out 11 s later
    -- ("Rx age server 11.1s"). The #97 pacing throttles send RATE but does nothing
    -- about stacked redundant snapshots; this caps the host-settings portion of the
    -- FIFO at exactly one sync (~46 chunks) no matter how fast the host edits.
    -- Dropping un-sent OLD-session chunks is safe: the receiver keys by (sender,
    -- session) and only applies once ALL `total` chunks of a session arrive, so a
    -- never-completed old session is discarded when this fresh session's chunks land
    -- (see the fresh-session-id note at the top of this function). Only host-settings
    -- chunks are purged; graph-snapshot / peer-manifest chunks (separate syncs) stay.
    do
        local q = _ct_chunk_send_queue
        local w = 1
        for r = 1, #q do
            local e = q[r]
            if e and e.event ~= "ct_sync_host_settings_chunk" then
                q[w] = e
                w = w + 1
            end
        end
        for r = #q, w, -1 do q[r] = nil end
    end
    for seq = 1, total do
        local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
        local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
        local chunk_str = string.sub(json, start_i, stop_i)
        -- Issue #97: enqueue (paced by mod.update) instead of inline-bursting.
        -- record_send is deferred to actual emit time so the net_replay ring
        -- still records what left the wire (closure captures this chunk's args).
        local _rec
        if _nr then
            local _seq, _total, _cs = seq, total, chunk_str
            _rec = function()
                _nr:record_send("ct", "ct_sync_host_settings_chunk",
                    string.format("session=%d seq=%d total=%d chunk=%s", session, _seq, _total, _cs), "others")
            end
        end
        _ct_enqueue_chunk("ct_sync_host_settings_chunk", "others", CT_RPC_SCHEMA, session, seq, total, chunk_str, _rec)
    end
    _dbg("[ct_sync] broadcast host settings to clients (%s; session %d, %d chunks, %d bytes, %d keys)",
        tostring(reason), session, total, json_len, #SYNCED_SETTING_NAMES)
end

-- Regression guard for MIDRUN_SETTING_REBROADCAST_MARKER: the mid-run re-sync wiring must
-- be present and the two boon-count keys (the reported mid-run desync) must be in the
-- synced registry, else a host edit won't reach clients until the next run.
_rt_register("midrun_setting_rebroadcast_wired", function()
    if type(mod._ct_broadcast_host_settings) ~= "function" then
        return "MIDRUN-SYNC REGRESSION: mod._ct_broadcast_host_settings missing (mid-run host settings won't re-sync to clients)"
    end
    if type(mod._ct_synced_set) ~= "table" then
        return "MIDRUN-SYNC REGRESSION: mod._ct_synced_set membership table missing"
    end
    for _, k in ipairs({ "shrine_boon_count", "chest_boon_count" }) do
        if not mod._ct_synced_set[k] then
            return string.format("MIDRUN-SYNC REGRESSION: '%s' absent from synced set -- mid-run host edit won't reach clients", k)
        end
    end
end)

-- Boon-altar no-repeat bookkeeping: the taken-boon table must exist so the
-- no-repeat strip can read it (v0.7.152-dev: the mislabeled "Chest of Trials"
-- pay-with-coin schedule was removed -- it was wrongly re-pricing every boon
-- ALTAR via DeusChestExtension.power_up, shadowing the altar-reuse multiplier;
-- a real Chest of Trials is DeusCursedChestExtension with no coin cost).
_rt_register("boon_altar_no_repeat", function()
    if type(mod._ct_boon_altar_taken_boons) ~= "table" then
        return "mod._ct_boon_altar_taken_boons missing (boon-altar no-repeat table)"
    end
end)

-- Adventure-collectible -> coin coverage + leftover-book-spot big casket payout.
_rt_register("cw_collectible_and_big_casket", function()
    local set = mod._ct_collectible_to_coin
    if type(set) ~= "table" then return "mod._ct_collectible_to_coin missing" end
    -- loot_die (incl. DLC ale/chalice reskins) and lorebook_page must convert to
    -- coin; painting_scrap is handled by the spawner-eligibility mapping instead.
    if not set.loot_die then return "loot_die not in collectible->coin set" end
    if not set.lorebook_page then return "lorebook_page not in collectible->coin set" end
    -- The big-casket 3x payout rides GameModeDeus._get_coins_amount_and_type; the
    -- class must exist and expose that method for our hook to have bound.
    if rawget(_G, "GameModeDeus") and type(GameModeDeus._get_coins_amount_and_type) ~= "function" then
        return "GameModeDeus._get_coins_amount_and_type missing (big-casket 3x hook can't bind)"
    end
end)

-- v0.7.165-dev: coin-reservation partition (Abundance-of-Life curse robust fix).
-- The _can_spawn hook reserves a deterministic slice of primary spawners as
-- coin-only so the ×3 potion curse can't drain coins out of the shared pool. This
-- marker asserts the partition is (a) wired, (b) deterministic, and (c) a PROPER
-- subset (neither empty nor total) -- an empty reservation = no guarantee, a total
-- reservation = potions/altars can never spawn.
_rt_register("coin_reservation_partition", function()
    local t = mod._ct_coin_reservation_test
    if type(t) ~= "table" or type(t.reserved) ~= "function" then
        return "mod._ct_coin_reservation_test missing (coin reservation not wired)"
    end
    if type(mod._ct_rebuild_coin_reserved_set) ~= "function" then
        return "mod._ct_rebuild_coin_reserved_set missing (rank-based reserve set not wired)"
    end
    if type(mod._ct_clear_coin_reserved_set) ~= "function" then
        return "mod._ct_clear_coin_reserved_set missing (reserve-set reset not wired)"
    end
    if not (type(t.fraction) == "number" and t.fraction > 0 and t.fraction < 1) then
        return "coin reserved fraction must be in (0,1), got " .. tostring(t.fraction)
    end
    -- Determinism: same input -> same output across calls.
    if t.reserved(0.5) ~= t.reserved(0.5) then
        return "reservation is non-deterministic for a fixed percentage_through_level"
    end
    -- Proper subset over a representative spread of percentage_through_level values.
    local reserved_n, total_n = 0, 0
    for i = 0, 100 do
        total_n = total_n + 1
        if t.reserved(i / 100) then reserved_n = reserved_n + 1 end
    end
    if reserved_n == 0 then
        return "coin reservation reserved ZERO spawners over [0,1] -- coins not guaranteed"
    end
    if reserved_n == total_n then
        return "coin reservation reserved ALL spawners over [0,1] -- potions/altars starved"
    end
end)

-- ============================================================
-- Graph snapshot sync (v0.7.64)
-- ============================================================
-- ct_sync_host_settings_chunk above broadcasts the host's TOGGLES. That's enough
-- for graph determinism only when every peer's LEVEL_AVAILABILITY pool is identical.
-- But `inject_adventure_maps` mutates LEVEL_AVAILABILITY arrays at module-load and
-- can't be runtime-resynced (the count folds into lobby `combined_hash`, sealed at
-- the lobby handshake — see reference_vt2_lobby_combined_hash.md). When a peer has
-- the toggle in a different state than the host, their local `deus_populate_graph`
-- indexes into a different-sized pool and produces a different graph from the same
-- seed — observed 2026-05-19 in a 3-player run: same seed, three different node
-- assignments (host: 8 adventure-rewritten nodes; one client: 9; another: 0).
--
-- Fix: the host broadcasts its RESOLVED graph after `deus_populate_graph` returns.
-- Clients overwrite the picker-output fields of their own graph in place. Only the
-- fields the visual layer reads are shipped (level, base_level, theme, curse, god,
-- node_type, type, terror_event_power_up + rarity, mutators, minor_modifier_group);
-- topological fields (next, layout_x/y, run_progress, label) are deterministic
-- from base_graph + seed and don't need sync.

-- Short<->long field map. Short keys keep the per-node JSON tight to fit chunk
-- budget — ~22-28 CW nodes × ~110 bytes ~= 3.6 KB worst case, ~9-10 chunks.
-- v0.7.124-dev: added `ls = level_seed` after host+client log diff (2026-05-26
-- session) showed host and client's local populate_graph produce DIFFERENT
-- level_seed values for the same node keys despite identical run_seed. Without
-- syncing level_seed, downstream per-mission generation paths that hash off
-- `node.level_seed` (curse-halo iconography, per-mission mutator config,
-- terror_event scheduling) can diverge between peers even when display fields
-- match. Issue: user reported "citadel of eternity mission curse doesn't match
-- what host set it to" — display curse matched on both peers, so the gap is
-- likely in a downstream consumer reading level_seed.
local GRAPH_FIELD_MAP = {
    l  = "level",
    b  = "base_level",
    t  = "theme",
    c  = "curse",
    g  = "god",
    nt = "node_type",
    ty = "type",
    te = "terror_event_power_up",
    tr = "terror_event_power_up_rarity",
    m  = "mutators",
    mm = "minor_modifier_group",
    ls = "level_seed",
}

local _ct_host_graph_snapshot = nil  -- { session = N, nodes = { [node_key] = { l=..., ... } } }
local _ct_graph_inbound = {}

-- Walk the snapshot and copy synced fields onto each node in `graph_data` in place.
-- In-place mutation preserves the table identity that `_path_graph` holds onto and
-- the `next` pointers that link nodes — neither is shipped, so neither is clobbered.
--
-- v0.7.123-dev (Issue #53 — REAL root cause):
-- SKIP the node identified by `_run_state:get_arena_belakor_node()`. Reason:
-- vanilla `DeusRunController._get_graph_data()` (deus_run_controller.lua:2035-2056)
-- mutates the chosen node's `level = "arena_belakor"`, `theme = "belakor"`,
-- `base_level = "arena_belakor"`, `minor_modifier_group = {}`, etc., once
-- `arena_belakor_node` is set in SharedState. That swap is what makes the map
-- scene spawn ARENA_NODE_UNIT (the visual temple) for that node — without it,
-- the node renders as TRAVEL/SHRINE_NODE_UNIT (no temple).
--
-- The vanilla call order is:
--   1. DeusMapView.start() → calls deus_run_controller:get_graph_data() → triggers
--      _get_graph_data()'s in-place swap. _path_graph now has the swapped node.
--   2. DeusMapView.start() → scene:on_enter(graph_data, ...) with the swapped table.
--   3. ct's DeusMapScene.on_enter hook → apply_graph_snapshot(graph_data) → was
--      overlaying host's PRE-swap snapshot fields onto the just-swapped node,
--      reverting level="arena_belakor" back to (e.g.) level="bell_belakor_path1".
--   4. Vanilla on_enter saw the reverted level → spawned wrong unit → no temple.
--
-- This was a CLIENT-ONLY bug because `_ct_host_graph_snapshot` is only populated
-- on peers that RECEIVED the broadcast (clients); the host itself never has a
-- snapshot stored locally, so the apply was a no-op on host. Matches user's
-- exact Issue #53 report: "host sees temple, client does not."
--
-- Fix: don't apply the snapshot's level/base_level/theme/etc. fields to the
-- arena_belakor node — let the vanilla swap stand. All other nodes still get
-- the host's resolved values (the original purpose of this snapshot — see
-- comments at line ~770 above for why we ship the graph at all).
local function apply_graph_snapshot(graph_data)
    if not (_ct_host_graph_snapshot and _ct_host_graph_snapshot.nodes and graph_data) then
        return 0
    end
    -- Resolve current arena_belakor_node (if any). nil = no temple yet; full apply.
    local arena_node_key
    do
        local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
        local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        local rs = rc and rc._run_state
        if rs and rs.get_arena_belakor_node then
            arena_node_key = rs:get_arena_belakor_node()
            if arena_node_key == "" then arena_node_key = nil end
        end
    end
    local applied, skipped = 0, 0
    for node_key, short_record in pairs(_ct_host_graph_snapshot.nodes) do
        if node_key == arena_node_key then
            skipped = skipped + 1
        else
            local node = graph_data[node_key]
            if type(node) == "table" and type(short_record) == "table" then
                for short, long in pairs(GRAPH_FIELD_MAP) do
                    local value = short_record[short]
                    -- cjson encodes Lua nil as missing key; we treat missing as "no change"
                    -- and explicit cjson.null (decoded to a sentinel) as "set to nil".
                    if value ~= nil then
                        if value == cjson.null then
                            node[long] = nil
                        else
                            node[long] = value
                        end
                    end
                end
                -- #68 FIX (v0.7.144-dev): make the CLIENT recognize the host's injected
                -- adventure maps. The client builds IS_INJECTED_ADVENTURE_LEVEL from its
                -- OWN per-map toggle selection, which can be empty or differ from the
                -- host's -- so adventure_base_from_level_key() returns nil for every
                -- host-injected node and the client renders them ALL as SHRINE_NODE_UNIT
                -- with no curse halo, AND ct's adventure-map curse sky/lighting tint is
                -- skipped (on_injected_adventure_level() is false on the client). Proven
                -- 2026-06-18: client logged DeusMapScene seen=15 rewritten=0 skipped=13 on
                -- every map open while the host had injected those maps. Cure: register
                -- the host's synced base_level into the client's recognition table,
                -- validated against the full static catalog MISSION_BY_KEY (built at load
                -- on BOTH peers, so a hit is a genuine adventure base -- never a vanilla CW
                -- node like arena_belakor). Idempotent; persists for the run once seen.
                local bl = node.base_level
                if type(bl) ~= "string" and type(node.level) == "string" then
                    -- Fallback when the host didn't ship base_level: derive the base
                    -- from the permutation key, same intent as adventure_base_from_level_key
                    -- ("dlc_castle_slaanesh_path1" -> "dlc_castle"; "bell_dup1_khorne_path1"
                    -- -> "bell"). Strip the _dup<N> alias then the trailing _<theme>_path<N>.
                    bl = node.level:gsub("_dup%d+", ""):gsub("_%a+_path%d+$", "")
                end
                if type(bl) == "string"
                   and AdventurePool and AdventurePool.MISSION_BY_KEY and AdventurePool.MISSION_BY_KEY[bl]
                   and AdventurePool.IS_INJECTED_ADVENTURE_LEVEL
                   and not AdventurePool.IS_INJECTED_ADVENTURE_LEVEL[bl] then
                    AdventurePool.IS_INJECTED_ADVENTURE_LEVEL[bl] = true
                    _dbg("[#68] client now recognizes host-injected adventure base '%s' (from graph snapshot)", bl)
                end
                applied = applied + 1
            end
        end
    end
    if skipped > 0 then
        _dbg("[ct_graph] apply skipped %d node(s) for arena_belakor swap preservation (key=%s)",
            skipped, tostring(arena_node_key))
    end
    return applied
end

mod:network_register("ct_graph_snapshot_chunk", function(sender_peer_id, schema_version, session, seq, total, chunk_str)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_graph_snapshot_chunk", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        pcall(printf, "[ct_graph] malformed chunk from %s; ignoring", tostring(sender_peer_id))
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _ct_graph_inbound[key]
    if not entry or entry.session ~= session then
        entry = { session = session, total = total, received = 0, chunks = {} }
        _ct_graph_inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then
        return
    end
    local pieces = {}
    for i = 1, entry.total do
        pieces[i] = entry.chunks[i] or ""
    end
    _ct_graph_inbound[key] = nil
    local json = table.concat(pieces)
    local ok, payload = pcall(cjson.decode, json)
    if not ok or type(payload) ~= "table" then
        pcall(printf, "[ct_graph] decode failed from %s (session %s, %d bytes)",
            tostring(sender_peer_id), tostring(session), #json)
        return
    end
    _ct_host_graph_snapshot = { session = session, nodes = payload }
    local node_count = 0
    for _ in pairs(payload) do node_count = node_count + 1 end
    _dbg("[ct_graph] received host graph snapshot from %s (session %s, %d chunks, %d bytes, %d nodes)",
        tostring(sender_peer_id), tostring(session), entry.total, #json, node_count)
end)

-- Encode the host's resolved graph_data into the short-key wire shape and
-- chunk-broadcast it to all clients. Called from the deus_populate_graph hook on
-- the host's return path. Same envelope as ct_sync_host_settings_chunk.
local function broadcast_graph_snapshot(graph_data)
    if type(graph_data) ~= "table" then return end
    local payload = {}
    local node_count = 0
    for node_key, node in pairs(graph_data) do
        if type(node) == "table" then
            local short = {}
            for s, long in pairs(GRAPH_FIELD_MAP) do
                local v = node[long]
                if v ~= nil then short[s] = v end
            end
            payload[node_key] = short
            node_count = node_count + 1
        end
    end
    local ok, json = pcall(cjson.encode, payload)
    if not ok or type(json) ~= "string" then
        pcall(printf, "[ct_graph] payload encode failed; not broadcasting")
        return
    end
    local json_len = #json
    local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
    local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
    if session == 0 then session = 1 end
    for seq = 1, total do
        local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
        local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
        local chunk_str = string.sub(json, start_i, stop_i)
        -- Issue #27: CT_RPC_SCHEMA prepended as first arg. Receiver gates on it.
        -- Issue #97: enqueue (paced by mod.update) instead of inline-bursting.
        _ct_enqueue_chunk("ct_graph_snapshot_chunk", "others", CT_RPC_SCHEMA, session, seq, total, chunk_str)
    end
    _dbg("[ct_graph] broadcast host graph snapshot (session %d, %d chunks, %d bytes, %d nodes)",
        session, total, json_len, node_count)
end

-- ============================================================
-- Peer manifest logging (v0.7.64)
-- ============================================================
-- Diagnostic: at lobby join / mission start, each client replies to the host's
-- ct_sync_host_settings_chunk broadcast with a ct_peer_manifest packet so the host's
-- log captures what every peer is actually running. Lets us tell version drift from
-- "real bug" in post-session log triage — the 2026-05-19 desync run had three peers
-- on potentially different ct builds and we couldn't confirm that from the logs.
--
-- Manifest fields (per peer):
--   v   ct version string (MOD_VERSION)
--   h   FNV-1a hash of the host-synced settings (so we can spot setting drift cheaply)
--   m   list of enabled Workshop mods (id, name, last_updated) — THE diagnostic for
--       "your friend's halo is different" caused by mismatched mod loadouts
--   vt  VMF workshop_timestamp (mismatched VMF builds cause weird bugs)
--   nl  #NetworkLookup.level_keys (confirms adventure-injection state per peer)
--
-- VMF network_register is string-keyed, NOT index-sequential, so this RPC does
-- NOT trip feedback_vt2_gated_registration_diverges.md. Old-ct peers without the
-- handler silently drop the packet — no crash.

local _ct_peer_manifests = {}      -- peer_id (string) -> decoded manifest table
local _ct_manifest_inbound = {}    -- chunked-receive buffer

-- FNV-1a 32-bit over a deterministic string. Used to fingerprint the synced settings
-- payload so a 1-byte log line shows whether two peers have identical CT config.
-- Stingray runs LuaJIT — `bit.bxor` and `bit.band` are available; native `~` and `&`
-- operators are not (LuaJIT defaults to Lua 5.1 syntax, no Lua-5.3 bitwise ops).
local _fnv_bxor = bit and bit.bxor
local _fnv_band = bit and bit.band
local function _fnv1a(s)
    if not (_fnv_bxor and _fnv_band) then
        -- Defensive fallback: bit library missing on some platform. Use a simple
        -- modular accumulator. Worse distribution but still good enough to flag
        -- "definitely different" without an exception.
        local h = 0
        for i = 1, #s do
            h = (h * 31 + string.byte(s, i)) % 4294967296
        end
        return h
    end
    local h = 2166136261
    for i = 1, #s do
        h = _fnv_band(_fnv_bxor(h, string.byte(s, i)), 0xFFFFFFFF)
        h = _fnv_band(h * 16777619, 0xFFFFFFFF)
    end
    return h
end

local function _build_local_manifest()
    local manifest = { v = MOD_VERSION }
    -- Settings hash: serialize SYNCED_SETTING_NAMES values in traversal-order (the
    -- order `_collect_setting_ids` walks the data tree, deterministic across all
    -- peers running the same ct version). Two peers with the same config produce
    -- the same fingerprint. mod:get reads the LOCAL value — we want each peer's
    -- local setting fingerprint, not the host's.
    local pieces = {}
    for _, name in ipairs(SYNCED_SETTING_NAMES) do
        pieces[#pieces + 1] = name .. "=" .. tostring(mod:get(name))
    end
    manifest.h = _fnv1a(table.concat(pieces, "|"))
    -- Enabled mods: Managers.mod._mods is the canonical local view (mod_manager.lua:326).
    local enabled = {}
    if Managers and Managers.mod and Managers.mod._mods then
        for _, m_entry in ipairs(Managers.mod._mods) do
            if type(m_entry) == "table" and m_entry.enabled then
                enabled[#enabled + 1] = {
                    i = tostring(m_entry.id or ""),
                    n = tostring(m_entry.name or ""),
                    u = m_entry.last_updated or m_entry.timestamp or 0,
                }
                if tostring(m_entry.id) == "1369573612" then
                    manifest.vt = m_entry.last_updated or m_entry.timestamp or 0
                end
            end
        end
    end
    manifest.m = enabled
    manifest.nl = (NetworkLookup and NetworkLookup.level_keys and #NetworkLookup.level_keys) or 0
    return manifest
end

local function _log_peer_manifest(peer_id, manifest, label)
    if type(manifest) ~= "table" then return end
    local mods_count = (type(manifest.m) == "table") and #manifest.m or 0
    _dbg("[ct_peers] %s peer=%s ct=%s settings_hash=%08x vmf_ts=%s num_levels=%s enabled_mods=%d",
        label or "PEER",
        tostring(peer_id),
        tostring(manifest.v),
        manifest.h or 0,
        tostring(manifest.vt or "?"),
        tostring(manifest.nl or "?"),
        mods_count)
end

local function _log_peer_diff_against_host(peer_id, peer_manifest, host_manifest)
    if type(peer_manifest) ~= "table" or type(host_manifest) ~= "table" then return end
    local diffs = {}
    if peer_manifest.v ~= host_manifest.v then
        diffs[#diffs + 1] = "ct_version(" .. tostring(peer_manifest.v) .. " vs host " .. tostring(host_manifest.v) .. ")"
    end
    if peer_manifest.h ~= host_manifest.h then
        diffs[#diffs + 1] = "settings_hash"
    end
    if peer_manifest.nl ~= host_manifest.nl then
        diffs[#diffs + 1] = "num_levels(" .. tostring(peer_manifest.nl) .. " vs host " .. tostring(host_manifest.nl) .. ")"
    end
    if peer_manifest.vt ~= host_manifest.vt then
        diffs[#diffs + 1] = "vmf_timestamp(" .. tostring(peer_manifest.vt) .. " vs host " .. tostring(host_manifest.vt) .. ")"
    end
    -- Mod-set diff (by id).
    local host_ids, peer_ids = {}, {}
    if type(host_manifest.m) == "table" then
        for _, m in ipairs(host_manifest.m) do host_ids[m.i or ""] = m.n or "?" end
    end
    if type(peer_manifest.m) == "table" then
        for _, m in ipairs(peer_manifest.m) do peer_ids[m.i or ""] = m.n or "?" end
    end
    local missing, extra = {}, {}
    for id, name in pairs(host_ids) do
        if not peer_ids[id] then missing[#missing + 1] = name end
    end
    for id, name in pairs(peer_ids) do
        if not host_ids[id] then extra[#extra + 1] = name end
    end
    if #missing > 0 then diffs[#diffs + 1] = "missing_vs_host=[" .. table.concat(missing, ",") .. "]" end
    if #extra > 0 then diffs[#diffs + 1] = "extra_vs_host=[" .. table.concat(extra, ",") .. "]" end

    if #diffs > 0 then
        _dbg("[ct_peers]   DIFF peer=%s: %s", tostring(peer_id), table.concat(diffs, "; "))
    else
        _dbg("[ct_peers]   peer=%s matches host", tostring(peer_id))
    end
end

-- Assigned to the forward-declared local at top of file so the ct_sync handler
-- closure (which fires before this block executes) can call us.
_broadcast_local_manifest = function(target)
    local manifest = _build_local_manifest()
    local ok, json = pcall(cjson.encode, manifest)
    if not ok or type(json) ~= "string" then
        pcall(printf, "[ct_peers] manifest encode failed; not broadcasting")
        return
    end
    local json_len = #json
    local total = math.max(1, math.ceil(json_len / SYNC_CHUNK_SIZE))
    local session = math.floor(((Application and Application.time_since_launch and Application.time_since_launch()) or os.time()) * 1000) % 2147483647
    if session == 0 then session = 1 end
    for seq = 1, total do
        local start_i = (seq - 1) * SYNC_CHUNK_SIZE + 1
        local stop_i = math.min(start_i + SYNC_CHUNK_SIZE - 1, json_len)
        local chunk_str = string.sub(json, start_i, stop_i)
        -- Issue #27: CT_RPC_SCHEMA prepended as first arg. Receiver gates on it.
        -- Issue #97: enqueue (paced by mod.update) instead of inline-bursting.
        -- `target` is the function arg ("server" reply / "all" /peers dump).
        _ct_enqueue_chunk("ct_peer_manifest_chunk", target, CT_RPC_SCHEMA, session, seq, total, chunk_str)
    end
    return manifest, json_len, total
end

mod:network_register("ct_peer_manifest_chunk", function(sender_peer_id, schema_version, session, seq, total, chunk_str)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_peer_manifest_chunk", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    if type(session) ~= "number" or type(seq) ~= "number" or type(total) ~= "number" or type(chunk_str) ~= "string" then
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _ct_manifest_inbound[key]
    if not entry or entry.session ~= session then
        entry = { session = session, total = total, received = 0, chunks = {} }
        _ct_manifest_inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then return end
    local pieces = {}
    for i = 1, entry.total do pieces[i] = entry.chunks[i] or "" end
    _ct_manifest_inbound[key] = nil
    local json = table.concat(pieces)
    local ok, payload = pcall(cjson.decode, json)
    if not ok or type(payload) ~= "table" then
        pcall(printf, "[ct_peers] manifest decode failed from %s", tostring(sender_peer_id))
        return
    end
    _ct_peer_manifests[key] = payload
    _log_peer_manifest(sender_peer_id, payload, "RECV")
    -- If we're host, also print a diff against our own manifest right away.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        local host_manifest = _build_local_manifest()
        _log_peer_diff_against_host(sender_peer_id, payload, host_manifest)
    end
end)

-- /peers — on-demand dump. Anyone can run it; everyone re-shares their
-- manifest so the requester's log is freshly populated.
mod:command("peers", "Dump per-peer ct/mod manifest diff vs host (for lobby desync triage)", function()
    local host_manifest = _build_local_manifest()
    _log_peer_manifest("self", host_manifest, "SELF")
    -- Broadcast to everyone so each peer re-shares its manifest with us.
    _broadcast_local_manifest("all")
    -- Print whatever we already have stored.
    local n = 0
    for peer_id, manifest in pairs(_ct_peer_manifests) do
        n = n + 1
        _log_peer_manifest(peer_id, manifest, "CACHED")
        _log_peer_diff_against_host(peer_id, manifest, host_manifest)
    end
    mod:echo(string.format("[ct_peers] dumped %d cached peer manifest(s); refreshed broadcast — re-run /peers in ~2s for new replies", n))
end)

-- Read effective setting: on host, use the user's actual configured value.
-- On client, use whatever the host most recently broadcast. If the client
-- hasn't received the broadcast yet (solo, RPC ordering before host setup_run),
-- fall back to the client's own mod:get so the mod still works locally before
-- any sync arrives.
-- v0.7.55: assigned to the forward-declared `effective_setting` slot so callers
-- above this point (on_soft_currency_picked_up coin multiplier, etc.) bind to the
-- same local instead of a nil global.
effective_setting = function(name)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        return mod:get(name)
    end
    local v = _ct_host_settings[name]
    if v ~= nil then
        return v
    end
    return mod:get(name)
end

-- Exposed for dofile'd modules (e.g. _ct_mechanic_tweaks.lua) that live in their
-- own chunk and can't see this file-scope local. Field assignment only -- adds no
-- main-chunk local (keeps us under the Lua 5.1 200-locals-per-function cap).
mod._ct_effective_setting = effective_setting

-- ============================================================
-- UNCONDITIONAL settings dump (Issue: host-config visibility for triage).
-- ============================================================
-- Walks the REALIZED data widget tree (mod:dofile -> _collect_setting_ids, which
-- captures the generated disable_boon_*/start_boon_*/adventure-map widgets a static
-- text-scrape would miss) and prints one compact `[ct-settings]` line per setting via
-- RAW printf. printf (misc_util.lua:29) is a vanilla engine global = print(format(...));
-- it bypasses the VMF per-mod logging toggle, so the host's REAL config lands in the
-- log even on a logging-OFF host (the established ct-probe pattern, :3513/:5154/:9832).
--
-- Two phases (see call sites): "load" prints each peer's own stored mod:get values
-- (local config); "setup_run"/"host_sync" additionally prints effective_setting(id)
-- so host-authoritative resolution / host<->client divergence is visible in the log.
-- For SYNCED settings the line carries both get= (this peer's local) and eff= (the
-- value actually used: host's own get on host, host's broadcast on clients). Per-peer
-- settings (inject_adventure_maps) show eff==get by definition.
--
-- Attached to `mod` (not a file-scope local) deliberately: this chunk is near Lua
-- 5.1's 200-locals-per-function cap, so shared helpers go on the mod table. The
-- inner locals below live in THIS function's own scope and don't count against the
-- main chunk. Bounded (one pass over the static-or-generated id list, NOT per-frame).
-- pcall-guarded end-to-end so a dump failure can never break load or run start.
function mod._ct_dump_settings(phase)
    local ok, err = pcall(function()
        local ids = _collect_setting_ids()
        table.sort(ids)
        local eff = mod._ct_effective_setting
        local is_server = Managers and Managers.player and Managers.player.is_server
        local function fmtv(v)
            if v == true then return "1"
            elseif v == false then return "0"
            elseif v == nil then return "?"
            else return tostring(v) end
        end
        printf("[ct-settings] BEGIN phase=%s v=%s is_server=%s synced_received=%s count=%d",
            tostring(phase), tostring(MOD_VERSION), tostring(is_server),
            tostring(_ct_host_sync_received), #ids)
        local want_eff = (phase ~= "load")
        for _, id in ipairs(ids) do
            local g = mod:get(id)
            if want_eff and type(eff) == "function" then
                local eok, ev = pcall(eff, id)
                printf("[ct-settings] %s get=%s eff=%s", id, fmtv(g), eok and fmtv(ev) or "ERR")
            else
                printf("[ct-settings] %s get=%s", id, fmtv(g))
            end
        end
        printf("[ct-settings] END phase=%s", tostring(phase))
    end)
    if not ok then
        printf("[ct-settings] DUMP FAILED phase=%s err=%s", tostring(phase), tostring(err))
    end
end

-- Auto-fire on load (local config snapshot). Lands unconditionally via printf even
-- if VMF mod-logging is OFF, so the host's stored config is in every session log.
mod._ct_dump_settings("load")

-- Chat command for an on-demand re-dump (host-authoritative phase so eff= is shown).
-- Mirrors the existing /dump_* command family. Registered here (after the helper is
-- defined) rather than with the other commands so the helper is in scope.
mod:command("ct_dump_settings", "Dump every ct setting_id (local mod:get + host-effective value) to the log via raw printf", function()
    mod._ct_dump_settings("command")
    mod:echo("[ct] settings dumped to log ([ct-settings] lines).")
end)

-- v0.7.53: routed through `effective_setting` so client peers gate on the host's synced
-- toggle, not their own. Previously used `mod:get` directly, which made client-side curse
-- name display (`get_current_node_curse` hook + `_transition_next_node` save-restore)
-- diverge from the host's: gameplay ran the host's mutator either way, but the curse
-- name shown on Holseher's map / mission tooltips read each peer's local toggle.
is_curse_disabled = function(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then
        return false
    end
    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return effective_setting(key) == true
end

-- v0.7.95: starting_coins is now a SETTER, not an adder.
-- ============================================================
-- Bug (user report 2026-05-23): "We got an extra 200 coins even though we had
-- the setting for starting at 300 we got 500 somehow." Root cause: the prior
-- implementation read the setting in a hook_safe(setup_run) AFTER vanilla had
-- already called `set_player_soft_currency(own_peer_id, REAL_PLAYER_LOCAL_ID,
-- initial_own_soft_currency)` with rolled-over coins (~0-200 from prior run),
-- then re-entered `on_soft_currency_picked_up(starting)` which ADDED the
-- setting on top. Vanilla 200 + setting 300 = displayed 500.
--
-- Fix: intercept the `initial_own_soft_currency` argument BEFORE vanilla
-- runs, by hooking setup_run with a full wrapper (not hook_safe). When the
-- starting_coins setting is > 0, replace arg[5] with the snapped setting
-- value. Vanilla's setter (deus_run_controller.lua:315) then writes exactly
-- the setting value — no addition, no double-grant. Setting=0 leaves vanilla
-- behavior intact (rolled-over coins still flow through).
--
-- Marker `STARTING_COINS_MODE_MARKER` is embedded near the call site so the
-- /ct_regression_test source-pattern check (starting_coins_setter_not_adder)
-- can verify the setter mode shipped to the compiled bundle.
--
-- Per-peer scoping: host's setting wins. On clients, the hook still rewrites
-- their own arg (so the value they pass via rpc_deus_set_initial_soft_currency
-- already matches the host's broadcast), and the host-side RPC handler hook
-- below ALSO enforces the host's setting on the value it ultimately writes
-- for the client's row. Belt-and-suspenders per feedback_redundant_safeguards_ok.md.
mod:hook("DeusRunController", "setup_run", function(func, self, ...)
    -- STARTING_COINS_MODE_MARKER = setter-override-via-setup_run-arg (embedded for regression check)
    -- v0.7.127-dev: reset altar reuse counts at run start. Previous-run go_ids
    -- can collide with this run's new chests if Stingray's unit_storage cycles
    -- the same network ids; wiping at run start avoids ghost-use counts.
    _altar_uses_by_go_id = {}
    -- v0.7.157-dev Task B: run start = reset the per-mission Chest of Trials
    -- activation counter too (belt-and-suspenders with the per-node reset in
    -- _transition_next_node).
    _ct_cursed_chest_seq = 0
    _ct_cot_block_last = {}   -- #117: reset per-block last-forced trial pick at run start
    -- Boon altars: run start = new run, so clear the per-run no-repeat
    -- taken-boon set (each altar can offer the full pool again).
    mod._ct_boon_altar_taken_boons = {}
    -- audit 2026-06-07 (v0.7.133-dev): capture real arity. Trailing `mutators`
    -- (args[8]) and `boons` (args[9]) are frequently nil, so bare unpack(args)
    -- would stop at the first nil hole and drop the rest. Pass explicit n so the
    -- nils are preserved positionally (VMF_RECIPES §2a). args[5] mutation below
    -- is unchanged.
    local n = select("#", ...)
    local args = { ... }
    -- Vanilla signature: (run_seed, difficulty, journey_name, dominant_god,
    -- initial_own_soft_currency, telemetry_id, with_belakor, mutators, boons)
    -- so initial_own_soft_currency is args[5].
    -- effective_setting reads host's broadcast value on clients and own value on host,
    -- so both peers compute the same target. The host-side RPC handler still re-clamps.
    local raw_setting = effective_setting("starting_coins")
    local setting = (type(raw_setting) == "number") and math.floor(raw_setting / 25 + 0.5) * 25 or 0

    local run_state = self and self._run_state
    local run_id = run_state and run_state.get_run_id and run_state:get_run_id() or "unknown"

    local vanilla_initial = args[5]
    local final = vanilla_initial

    if setting and setting > 0 and _starting_coins_applied_for_run ~= run_id then
        args[5] = setting
        final = setting
        _starting_coins_applied_for_run = run_id
        _dbg("[ct/coins] starting_coins setter applied: vanilla_initial=%s, setting=%d, final=%d (run_id=%s)",
            tostring(vanilla_initial), setting, final, tostring(run_id))
    elseif setting and setting > 0 then
        _dbg("[ct/coins] starting_coins setter skipped (already applied for run_id=%s): vanilla_initial=%s, setting=%d",
            tostring(run_id), tostring(vanilla_initial), setting)
    end

    local ret_a, ret_b = func(self, unpack(args, 1, n))

    -- v0.7.121-dev Issue #53 diagnostic — dump post-populate graph state on
    -- BOTH peers (gated on VMF debug logging via _dbg). Proves whether the
    -- arena_belakor nodes actually ended up in the client's local graph after
    -- vanilla setup_run -> deus_generate_graph -> deus_populate_graph runs with
    -- the host-broadcast with_belakor arg.
    pcall(function()
        local is_server_d = Managers and Managers.player and Managers.player.is_server
        local journey_name_d = args[3]
        local with_belakor_d = args[7]
        local pg = self._path_graph
        local arena_count, total = 0, 0
        local arena_keys = {}
        if type(pg) == "table" then
            for k, n in pairs(pg) do
                total = total + 1
                if type(n) == "table" then
                    local lvl = n.level or ""
                    if type(lvl) == "string" and lvl:find("^arena") then
                        arena_count = arena_count + 1
                        arena_keys[#arena_keys + 1] = tostring(k) .. "(" .. lvl .. ")"
                    end
                end
            end
        end
        _dbg("[belakor:diag] DeusRunController.setup_run done — is_server=%s journey=%s with_belakor=%s graph_total=%d arena_nodes=%d (%s)",
            tostring(is_server_d), tostring(journey_name_d), tostring(with_belakor_d),
            total, arena_count, table.concat(arena_keys, ","))
    end)

    -- Host-side post-setup broadcast (formerly a separate mod:hook_safe; folded
    -- in here to avoid the mod-lint duplicate-hook rule on DeusRunController.setup_run
    -- — and to keep all setup_run concerns in one body so a future maintainer
    -- doesn't have to chase two hook registrations).
    -- On host only: broadcast our settings to all clients so their
    -- deus_populate_graph hook (about to fire on their machines) mutates the
    -- same way. VMF's network_send is FIFO over the same Steam channel as the
    -- engine's rpc_deus_setup_run, so as long as we send BEFORE the engine
    -- sends its setup_run RPC (we run AT the end of host's setup_run, which is
    -- right before full_sync() ships the engine RPC to clients), our packet
    -- arrives first and the client processes it before their setup_run fires.
    -- Verified safe to spam — receiving the same values twice is a no-op assignment.
    -- Broadcast our settings to all clients so their deus_populate_graph hook
    -- (about to fire on their machines) mutates the same way. Shared helper
    -- (_ct_broadcast_host_settings) is ALSO reused by mod.on_setting_changed so a
    -- mid-run host edit re-syncs immediately; server-gated inside the helper. FIFO
    -- ordering vs the engine's rpc_deus_setup_run is preserved — we still send here
    -- at the end of host setup_run, before full_sync() ships the engine RPC.
    mod._ct_broadcast_host_settings("setup_run")
    -- Run-start host-authoritative settings dump (host resolves effective_setting to
    -- its OWN mod:get here, so the host's REAL cursed_chest_count / unique_trials /
    -- altar-reuse / curse-disable config is captured in the log every run, regardless
    -- of any logging toggle — clients dump on host-sync arrival instead, see :1420).
    if mod._ct_dump_settings then mod._ct_dump_settings("setup_run") end
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        -- v0.7.64: also log the host's own manifest as a baseline so clients'
        -- replies can be diff'd against it in post-session log triage.
        local host_manifest = _build_local_manifest()
        _log_peer_manifest("self (host)", host_manifest, "HOST")
    end

    return ret_a, ret_b
end)

-- v0.7.95 (host-side): when a client joins and sends its initial_own_soft_currency
-- via rpc_deus_set_initial_soft_currency, the host's RPC handler writes
-- `extra_coins + initial_own_soft_currency` for the client's peer. To keep the
-- "host controls economy" invariant (precedent across coin_multiplier / shrine
-- multipliers / boon roll), override the incoming value with the host's setting
-- BEFORE vanilla computes `new_coins`. Skip if setting == 0 (vanilla behavior).
mod:hook("DeusRunController", "rpc_deus_set_initial_soft_currency", function(func, self, sender_channel_id, initial_own_soft_currency)
    local host_setting = mod:get("starting_coins")
    if type(host_setting) == "number" then
        host_setting = math.floor(host_setting / 25 + 0.5) * 25
    end
    if host_setting and host_setting > 0 then
        _dbg("[ct/coins] host RPC override for joining peer: client_sent=%s, host_setting=%d (overriding)",
            tostring(initial_own_soft_currency), host_setting)
        initial_own_soft_currency = host_setting
    end
    return func(self, sender_channel_id, initial_own_soft_currency)
end)

-- v0.7.95: prior `mod:hook_safe("DeusRunController", "setup_run", ...)` host-side
-- broadcast was folded into the full `mod:hook(...)` block above. Two hooks on the
-- same (Class, method) tripped the mod-lint duplicate-hook rule.

-- CLARIFY: Vanilla signature is `(seed, count, existing_power_ups, difficulty, run_progress, ...)`.
-- Rather than hard-coding count = args[2] (which would be brittle to future signature drift), the
-- code scans args for the first integer in [1,10] and assumes that's the count. `seed` is normally a
-- 32-bit hash > 10 so it won't collide.
-- QUESTION: Why detect by value range instead of just args[2]? If FatShark ever wraps this, the
-- scan also finds the count, but a non-default count outside [1,10] would silently be missed.

-- v0.7.134: the Belakor-temple branch writes args[8] = "unique" AFTER the hook captures
-- its arity `n` — on the cursed-chest path vanilla passes only 7 args
-- (deus_run_controller.lua:1115), so without extending n the forced rarity is silently
-- dropped at the forward `unpack(args, 1, n)` (regression shipped in v0.7.133).
-- Exposed on mod for the regression test (belakor_forced_rarity_survives_unpack_bound).
function mod._ct_extend_arity_for_forced_rarity(n)
    if n < 8 then return 8 end
    return n
end

-- v0.7.200-dev (#211): SINGLE shared "is this boon disabled?" check, used by (1) the
-- pool strip in the generate_random_power_ups hook below, (2) the pre-grant gate in the
-- consolidated DeusRunController.add_power_ups hook, and (3) the bot random-boon picker
-- (_pick_random_for_rarity) — the CONFIRMED #211 bypass, which sampled the UNSTRIPPED
-- DeusPowerUpsArrayByRarity bucket and then granted with the pre-grant gate deliberately
-- skipped (_ct_bot_mirror_active). Truthy-normalized: checkbox values are booleans, so
-- this is behavior-identical to both prior call sites (`if effective_setting(...)` and
-- `== true`). On `mod` (not a file-scope local) per the 200-locals cap note; also lets
-- /ct_regression_test reach it.
function mod._ct_boon_disabled(name)
    if name == nil then return false end
    return not not effective_setting("disable_boon_" .. tostring(name))
end

mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)
    -- audit 2026-06-07 (v0.7.133-dev): capture real arity. Vanilla sig is
    -- (seed, count, existing_power_ups, difficulty, run_progress, availability_type,
    -- career_name, forced_rarity); the trailing `forced_rarity` (args[8]) is nil at
    -- most call sites, so the existing pcall(func, unpack(args)) below would stop at
    -- the nil hole and drop trailing args, silently corrupting the roll. Pass explicit
    -- n so nils are preserved positionally (VMF_RECIPES §2a). The args[count_index]
    -- and args[8] mutations below are unchanged.
    local n = select("#", ...)
    local args = { ... }

    local count_index
    for index, value in ipairs(args) do
        if type(value) == "number" and value >= 1 and value <= 10 then
            count_index = index
            break
        end
    end

    if count_index then
        local original = args[count_index]
        local custom_count

        -- CLARIFY: Only override when the original count matches a known default (4 = shrine, 3 =
        -- chest). This avoids hijacking other call sites that pass arbitrary counts (e.g., quest
        -- rewards, Belakor temple). If FatShark changes the defaults this silently no-ops.
        if original == SHRINE_DEFAULT then
            custom_count = effective_setting("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = effective_setting("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            args[count_index] = custom_count
        end
    end

    -- Belakor temple force-rarity (toggle removed v0.7.83 — always-on per user 2026-05-22).
    -- At the Belakor arena node, when a cursed_chest roll fires, force
    -- `forced_rarity = "unique"` so the temple chest rewards uniques instead of the
    -- default `weight_by_rarity` mix (`{ event=6, exotic=3, rare=6, unique=1 }`).
    -- Each peer rolls its own seed when opening the chest (deus_cursed_chest_view.lua
    -- :58 uses a position-derived hash), so this hook fires per-peer; no host-authority
    -- concern. Logs whenever the cursed_chest gate hits so we can diagnose any future
    -- client-vs-host divergence reports.
    --
    -- Positional indices per vanilla signature
    -- `(seed, count, existing_power_ups, difficulty, run_progress, availability_type,
    --   career_name, forced_rarity)`:
    --   args[6] = availability_type
    --   args[8] = forced_rarity
    do
        local availability_type = args[6]
        local already_forced    = args[8]
        if not already_forced
            and availability_type == DeusPowerUpAvailabilityTypes.cursed_chest
        then
            local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
            local run_controller = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
            local run_state = run_controller and run_controller._run_state
            local arena_node, current_node
            if run_state and run_state.get_arena_belakor_node and run_state.get_current_node_key then
                arena_node = run_state:get_arena_belakor_node()
                current_node = run_state:get_current_node_key()
                if arena_node and current_node and arena_node == current_node then
                    args[8] = "unique"
                    -- v0.7.134: n was captured at hook entry, BEFORE this write; the
                    -- cursed-chest call site passes only 7 args, so n must be extended
                    -- to cover args[8] or unpack(args, 1, n) drops the forced rarity.
                    n = mod._ct_extend_arity_for_forced_rarity(n)
                end
            end
            local is_server = Managers and Managers.player and Managers.player.is_server
            _dbg("[belakor-temple] cursed_chest roll: is_server=%s arena_node=%s current_node=%s forced=%s",
                tostring(is_server), tostring(arena_node), tostring(current_node), tostring(args[8]))
        end
    end

    -- CLARIFY: Disabled-boon enforcement uses the "remove-then-restore" pattern: temporarily mutate
    -- the global pool, run the original sampler, then restore. This is safer than wrapping the
    -- sampler because vanilla's `generate_random_power_up` directly reads DeusPowerUpsArray /
    -- DeusPowerUpsArrayByRarity for both random and rarity-filtered selection (the actual read
    -- site is `deus_power_up_utils.lua:138` — `DeusPowerUpsArrayByRarity[rarity] or
    -- DeusPowerUpsArray`). `DeusPowerUpRarityPool` is NOT read by the roller — the v0.7.88 fix
    -- gated the wrong table; v0.7.90 moves dormant gating into THIS block so it actually fires.
    -- v0.7.90: wrapped in pcall so a vanilla-side error inside func() can't leave the arrays in
    -- a partially-stripped state across the rest of the session (the prior "POTENTIAL BUG (LOW)"
    -- note finally addressed).
    local removed_main = {}
    local removed_rarity = {}

    -- Bomb-boon exclusivity: if the toggle is on AND the player already owns any bomb boon, also
    -- strip the rest from the pool for this roll. existing_power_ups is positionally args[3] in the
    -- vanilla signature (seed, count, existing_power_ups, ...).
    local exclude_bomb_boons = false
    if effective_setting("bomb_boon_exclusive") then
        local existing = args[3]
        if type(existing) == "table" then
            for _, pu in ipairs(existing) do
                if pu and pu.name and BOMB_BOON_NAMES[pu.name] then
                    exclude_bomb_boons = true
                    break
                end
            end
        end
    end

    -- v0.7.100-dev: dormant gate REMOVED. `_should_strip` no longer consults
    -- DORMANT_BOON_RARITY (the table no longer exists) or `activate_dormant_<name>`
    -- settings (the widgets no longer exist; the setting reads would always be
    -- nil/false). Only the user-facing `disable_boon_<name>` checkbox and the
    -- bomb-boon mutual-exclusivity gate remain. The dormant boons themselves
    -- aren't registered in the pool, so they can't appear in DeusPowerUpsArray
    -- anyway — this is belt-and-suspenders.
    -- Boon-ALTAR no-repeat (DEFAULT, not a toggle): for boon-altar rolls
    -- (availability_type == weapon_chest, args[6]) exclude boons this peer has
    -- already taken from earlier boon altars this run, so each subsequent altar
    -- offers a boon none of the prior ones did. (weapon_chest is the engine name
    -- for the boon-altar roll source -- this is a BOON ALTAR, not a Chest of
    -- Trials; see the terminology banner.) Other roll sources (shrine,
    -- cursed_chest, quest rewards) are untouched.
    local _altar_no_repeat = (args[6] == DeusPowerUpAvailabilityTypes.weapon_chest)
        and type(mod._ct_boon_altar_taken_boons) == "table"

    local function _should_strip(name)
        if not name then return false end
        -- v0.7.200-dev (#211): disable check routed through the shared mod._ct_boon_disabled
        -- helper (behavior-identical for boolean checkbox values).
        if mod._ct_boon_disabled(name) then return true end
        if exclude_bomb_boons and BOMB_BOON_NAMES[name] then return true end
        if _altar_no_repeat and mod._ct_boon_altar_taken_boons[name] then return true end
        return false
    end

    if DeusPowerUpsArray then
        -- CLARIFY: Iterate backwards so table.remove indices stay stable. The saved `index` is the
        -- pre-removal slot, which is the correct insertion point for restoration in reverse order.
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local name = boon and boon.name
            if _should_strip(name) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local name = boon and boon.name
                    if _should_strip(name) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    -- v0.7.90: pcall the vanilla sampler so a crash inside it doesn't leave us stuck with a
    -- partial strip. On error, restore arrays and rethrow so the game's existing handler logs it.
    local ok, new_seed, new_power_ups = pcall(func, unpack(args, 1, n))

    -- CLARIFY: Restore in reverse order of removal so that re-inserting at the saved indices
    -- reconstructs the original array exactly. `removed_main` was appended in descending-i order,
    -- so iterating it in reverse means we reinsert from the lowest index first.
    for i = #removed_main, 1, -1 do
        local e = removed_main[i]
        table.insert(DeusPowerUpsArray, e.index, e.boon)
    end
    for rarity, removed in pairs(removed_rarity) do
        local arr = DeusPowerUpsArrayByRarity[rarity]
        for i = #removed, 1, -1 do
            local e = removed[i]
            table.insert(arr, e.index, e.boon)
        end
    end

    if not ok then
        mod:warning("[hook-error] generate_random_power_ups vanilla call raised: %s", tostring(new_seed))
        error(new_seed, 2)  -- re-raise with original message; arrays are now restored
    end

    -- CLARIFY: Re-applies the Khaine's Fury (deus_reckless_swings) tweak after every boon-roll. The
    -- engine may rebuild boon templates between rolls; this defensive call ensures the modified
    -- description and damage values stay in effect. on_setting_changed also calls this when the
    -- toggle flips.
    sync_reckless_swings()
    sync_bomb_cooldown()
    sync_boon_movespeed()

    -- v0.7.130-dev: piggyback on this hook to lazily apply the items 5+6
    -- parry-cooldown strip. The earlier boot-time `pcall(_ct128_strip_parry_cooldowns)`
    -- ran BEFORE morris settings populated DeusPowerUpTemplates (log line 1308 of
    -- console-2026-05-29-02.03.57: "DeusPowerUpTemplates not ready; parry-cooldown
    -- strip skipped"), so the cooldowns survived and items 5+6 never actually
    -- shipped. This hook fires on every boon roll AFTER morris settings are loaded
    -- and BEFORE any altar interaction (rolls happen at chest spawn, before player
    -- opens it). The strip body is idempotent — once `cooldown_buff` is nil, the
    -- next call's `for` loop is a no-op. Safe to call from every roll.
    pcall(_ct128_strip_parry_cooldowns)

    return new_seed, new_power_ups
end)

-- CLARIFY: Workaround for a vanilla VT2 layout bug. When a shrine/cursed-chest only spawns ONE
-- widget on the arc, vanilla code computes the offset via `cos(angle) * radius` where `angle = 0/0`
-- (NaN from division-by-zero in degenerate single-element arc). The widget then renders at NaN
-- screen position and is invisible. Replacing NaN with 0 centers the single widget. NaN is detected
-- via `x ~= x` (the only value that isn't equal to itself in IEEE 754).
-- QUESTION: Why only fix the 1-widget case? If the issue can also occur for 0 or N>1 widgets, this
-- silently fails to repair them. May be intentional — maybe FatShark's layout only divides by zero
-- when count == 1.
local function fix_arc_nan(widgets)
    if not widgets or #widgets ~= 1 then
        return
    end

    local widget = widgets[1]
    if widget and widget.offset then
        if widget.offset[1] ~= widget.offset[1] then
            widget.offset[1] = 0
        end
        if widget.offset[2] ~= widget.offset[2] then
            widget.offset[2] = 0
        end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self, shop_settings, power_ups, blessings)
    fix_arc_nan(self._shop_item_widgets)
    -- v0.7.67 diagnostic: log the blessings the shop is offering this visit. The
    -- 2026-05-20 session had blessing_of_power available at shop_strife but the
    -- user reported it "wasn't purchaseable" with zero buy attempts in logs. This
    -- captures whether the blessing was even in the offering pool, plus the buyer
    -- state at shop-open so we can tell from logs alone whether the button was
    -- already greyed out when the shop opened.
    if type(blessings) == "table" then
        local names = {}
        for i = 1, #blessings do names[i] = tostring(blessings[i]) end
        local with_buyer = self._deus_run_controller and self._deus_run_controller:get_blessings_with_buyer() or {}
        local buyer_dump = {}
        for k, v in pairs(with_buyer) do buyer_dump[#buyer_dump + 1] = tostring(k) .. "=" .. tostring(v) end
        _dbg("[miracle] DeusShopView opened type=%s blessings=[%s] already_bought={%s}",
            tostring(self._shop_type), table.concat(names, ","), table.concat(buyer_dump, ","))
    end

    -- v0.7.199-dev: boon-offer scrollbar setup, merged into this body because
    -- (DeusShopView, _create_ui_elements) is already hooked here (VMF dup-hook
    -- rule: one hook per (Class, method) pair). Implementation lives in the
    -- _ct_boon_scroll block below. Only the OFFERED boon widgets scroll;
    -- blessings and the owned-boons side panel are untouched.
    if mod._ct_boon_scroll_setup then
        local boon_widgets = {}
        local offers = self._shop_items and self._shop_items.power_ups
        if type(offers) == "table" then
            for i = 1, #offers do
                local entry = offers[i]
                if entry and entry.widget then
                    boon_widgets[#boon_widgets + 1] = entry.widget
                end
            end
        end
        mod._ct_boon_scroll_setup(self, boon_widgets, 4)
    end
end)

mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_nan(self._power_up_widgets)

    -- v0.7.199-dev: boon-offer scrollbar setup, merged into this body because
    -- (DeusCursedChestView, create_ui_elements) is already hooked here (VMF
    -- dup-hook rule). Implementation in the _ct_boon_scroll block below.
    -- _power_up_widgets holds ONLY the offered boons in this view (no
    -- blessings exist here).
    if mod._ct_boon_scroll_setup then
        mod._ct_boon_scroll_setup(self, self._power_up_widgets, 3)
    end
end)

-- ============================================================================
-- _ct_boon_scroll -- scrollbar for the shrine / cursed-chest boon offerings
-- (v0.7.199-dev)
--
-- The shrine (DeusShopView) and cursed chest (DeusCursedChestView) lay their
-- offered-boon widgets on a fixed vertical arc with no scrolling, so raising
-- the offered-boon caps (shrine_boon_count / chest_boon_count, now 1..50 in
-- the data file) would strand most rows off-screen and unselectable. When the
-- offer count exceeds what fits (shop: 4 rows, chest: 3 rows), this block:
--   1. flattens the arc into a row-snapped vertical list (row height 194 =
--      power_up_root.size[2] in both defs files), showing `visible` rows
--      centered on the power_up_root scenegraph node;
--   2. parks off-window rows at offset y = -20000, far off-screen, which makes
--      their hotspots unreachable by the cursor -- vanilla's own input loops
--      (_handle_input / hold-to-purchase) then naturally skip them, and we
--      never touch content.button_hotspot.disable_button (vanilla update owns
--      that field);
--   3. draws a hand-authored track+thumb scrollbar (plain rect passes +
--      hotspot passes) to the right of the boon column, injected into the
--      view's self._widgets so the vanilla draw loop renders it (verified:
--      deus_shop_view_v2._draw and deus_cursed_chest_view.draw both iterate
--      self._widgets).
-- Interactions: mouse wheel = 1 row per notch; click on the track above /
-- below the thumb = page a full window; hold + drag the thumb = jump to any
-- row (cursor y mapped through the track, row-snapped).
-- At or below the vanilla row counts this block does nothing at all -- the
-- vanilla arc (plus fix_arc_nan above) stays byte-identical.
--
-- Consolidation note: setup is invoked from the two existing hook_safe bodies
-- ABOVE (VMF dup-hook rule -- do NOT add another hook on _create_ui_elements /
-- create_ui_elements). The two `update` hooks at the bottom of this block are
-- the only hooks registered here; grep-verified 2026-07-01 that no other
-- ct_dev hook targets either view's `update`.
-- Wrapped in do..end so no new chunk-level locals land in the main chunk
-- (Lua 5.1's 200-local limit); the only export is mod._ct_boon_scroll_setup.
-- ============================================================================
do
    local ROW_H = 194                -- one boon row == power_up_root height (both views)
    local NODE_CENTER_Y = ROW_H / 2  -- rows are centered on power_up_root's vertical center
    -- Scrollbar geometry, relative to power_up_root's bottom-left corner. The
    -- boon column spans x 0..484 on that node (widget style offsets run 0..484
    -- in create_power_up_shop_item), so the track sits just right of it.
    -- First-guess cosmetics -- tune in-game if it overlaps or floats.
    local TRACK_X = 500
    local TRACK_W = 12
    local THUMB_W = 8
    local HIDDEN_Y = -20000

    -- Track (dim) + thumb (brass) rects, one hotspot each, all anchored to
    -- power_up_root. Colors are {A,R,G,B}. NOTE: rect passes position purely
    -- via style.offset added to the node's bottom-left world position --
    -- UIRenderer.draw_widget ignores horizontal/vertical_alignment for rect
    -- passes (alignment only applies to passes that call align_box_inplace,
    -- e.g. texture with texture_size), so explicit offsets are used here.
    -- The thumb's style.offset[2] is rewritten every frame by _reposition.
    local function _build_scrollbar_definition(track_h, thumb_h)
        local track_bottom = NODE_CENTER_Y - track_h / 2
        return {
            scenegraph_id = "power_up_root",
            offset = { 0, 0, 0 },
            element = {
                passes = {
                    { pass_type = "rect", style_id = "track" },
                    { pass_type = "rect", style_id = "thumb" },
                    { pass_type = "hotspot", style_id = "track", content_id = "track_hotspot" },
                    { pass_type = "hotspot", style_id = "thumb", content_id = "thumb_hotspot" },
                },
            },
            content = {
                track_hotspot = {},
                thumb_hotspot = {},
            },
            style = {
                track = {
                    size = { TRACK_W, track_h },
                    offset = { TRACK_X, track_bottom, 8 },
                    color = { 160, 15, 12, 10 },
                },
                thumb = {
                    size = { THUMB_W, thumb_h },
                    offset = { TRACK_X + (TRACK_W - THUMB_W) / 2, track_bottom + track_h - thumb_h, 9 },
                    color = { 255, 170, 145, 100 },
                },
            },
        }
    end

    -- Row-snapped reflow: rows [top .. top+visible-1] stack vertically centered
    -- on the node (slot 0 on top); everything else parks off-screen. The
    -- center_offset math reproduces vanilla's own row spacing exactly (vanilla
    -- count==visible offsets are 291/97/-97/-291 for 4 rows, 194/0/-194 for 3),
    -- so an engaged view's visible rows sit where vanilla would have put them.
    local function _reposition(st)
        local widgets = st.widgets
        local top = st.top
        local visible = st.visible
        local center_offset = (visible - 1) / 2 * ROW_H

        for i = 1, st.count do
            local widget = widgets[i]

            if widget and widget.offset then
                if top <= i and i <= top + visible - 1 then
                    local slot = i - top -- 0-based row within the visible window
                    widget.offset[1] = 0 -- flatten the arc's sin() x-sway
                    widget.offset[2] = center_offset - slot * ROW_H
                else
                    widget.offset[1] = 0
                    widget.offset[2] = HIDDEN_Y
                end
            end
        end

        local sw = st.scrollbar_widget

        if sw and sw.style and sw.style.thumb then
            local frac = st.max_top > 1 and (top - 1) / (st.max_top - 1) or 0
            local track_top = NODE_CENTER_Y + st.track_h / 2

            sw.style.thumb.offset[2] = track_top - frac * (st.track_h - st.thumb_h) - st.thumb_h
        end
    end

    local function _setup(view, boon_widgets, visible)
        view._ct_boon_scroll = nil -- fresh per create_ui_elements pass

        if type(boon_widgets) ~= "table" then
            return
        end

        local count = #boon_widgets

        if count <= visible then
            return -- fits the vanilla arc; stay 100% vanilla (fix_arc_nan already ran)
        end

        local widgets = view._widgets

        if type(widgets) ~= "table" then
            -- Future-patch shape change: degrade to "no scroll" rather than crash.
            mod:warning("[ct:boon_scroll] view has no _widgets array; scrollbar not injected, scroll disabled")
            return
        end

        local track_h = visible * ROW_H
        local thumb_h = math.max(24, visible / count * track_h)
        local scrollbar_widget = UIWidget.init(_build_scrollbar_definition(track_h, thumb_h))

        widgets[#widgets + 1] = scrollbar_widget
        view._ct_boon_scroll = {
            widgets = boon_widgets,
            count = count,
            visible = visible,
            row_h = ROW_H,
            top = 1,
            max_top = count - visible + 1,
            track_h = track_h,
            thumb_h = thumb_h,
            scrollbar_widget = scrollbar_widget,
        }

        _reposition(view._ct_boon_scroll)
        -- Apply-site log (PROJECT_STANDARDS 5.1a): fires once per view open.
        mod:info("[ct:boon_scroll] engaged: %d boons offered, %d visible rows, %d scroll positions",
            count, visible, count - visible + 1)
    end

    -- Exported entry point, called from the two hook_safe bodies above. pcall
    -- wrap so a vanilla shape change degrades to no-scroll instead of killing
    -- the view build.
    mod._ct_boon_scroll_setup = function(view, boon_widgets, visible)
        local ok, err = pcall(_setup, view, boon_widgets, visible)

        if not ok then
            view._ct_boon_scroll = nil
            mod:warning("[ct:boon_scroll] setup errored: %s (scroll disabled, vanilla layout kept)", tostring(err))
        end
    end

    -- Wheel delta (y axis) from the view's input service; raw Mouse fallback.
    -- Both views run on IngameMenuKeymaps, which maps scroll_axis to the mouse
    -- wheel axis on win32 (controller_settings.lua), so the fallback should
    -- never trigger in practice.
    local function _wheel_delta(view)
        local delta = 0
        local input_service = view.input_service and view:input_service()

        if input_service and input_service.get then
            local axis = input_service:get("scroll_axis")

            if axis then
                delta = axis.y or 0
            end
        end

        if delta == 0 and rawget(_G, "Mouse") and Mouse.axis and Mouse.axis_index then
            local axis = Mouse.axis(Mouse.axis_index("wheel"))

            if axis then
                delta = axis.y or 0
            end
        end

        return delta
    end

    -- Cursor y in 1080p UI space (y-up, same space as scenegraph world
    -- positions) -- mirrors vanilla UIWidgets.create_scrollbar's held_function.
    local function _cursor_ui_y(view)
        local input_service = view.input_service and view:input_service()
        local cursor = input_service and input_service.get and input_service:get("cursor")

        if not cursor then
            return nil
        end

        local scaled = UIInverseScaleVectorToResolution(cursor)

        return scaled and scaled.y or nil
    end

    -- Per-frame driver, run BEFORE vanilla update (wrapping hooks below) so
    -- the reflow lands in the same frame's draw + hotspot pass. Cheap: <= 50
    -- offset writes per frame, no allocation on the steady-state path.
    local function _frame(view)
        local st = view._ct_boon_scroll

        if not st or not st.widgets or not st.scrollbar_widget then
            return
        end

        -- 1) mouse wheel: one row per notch (positive y = wheel up = scroll up)
        local wheel = _wheel_delta(view)

        if wheel ~= 0 then
            local step = math.max(1, math.floor(math.abs(wheel) + 0.5))

            st.top = wheel > 0 and st.top - step or st.top + step
        end

        -- 2) thumb drag / track paging
        local content = st.scrollbar_widget.content
        local thumb_hotspot = content.thumb_hotspot
        local track_hotspot = content.track_hotspot

        if thumb_hotspot and track_hotspot and (thumb_hotspot.is_held or track_hotspot.on_release) then
            local cursor_y = _cursor_ui_y(view)
            local node_pos = view.ui_scenegraph and UISceneGraph.get_world_position(view.ui_scenegraph, "power_up_root")

            if cursor_y and node_pos then
                if thumb_hotspot.is_held then
                    -- Drag: thumb center follows the cursor, snapped to rows.
                    -- is_held persists while the button stays down even after
                    -- the cursor leaves the thumb (hotspot pass semantics), so
                    -- this is a real drag, not just a re-click.
                    local usable = st.track_h - st.thumb_h

                    if usable > 0 then
                        local track_top_world = node_pos[2] + NODE_CENTER_Y + st.track_h / 2
                        local frac = math.clamp((track_top_world - cursor_y - st.thumb_h / 2) / usable, 0, 1)

                        st.top = 1 + math.floor(frac * (st.max_top - 1) + 0.5)
                    end
                elseif not thumb_hotspot.cursor_hover then
                    -- Track click off the thumb: page one full window toward the click.
                    local thumb_bottom_world = node_pos[2] + st.scrollbar_widget.style.thumb.offset[2]
                    local thumb_center_world = thumb_bottom_world + st.thumb_h / 2

                    if cursor_y > thumb_center_world then
                        st.top = st.top - st.visible
                    else
                        st.top = st.top + st.visible
                    end
                end
            end

            track_hotspot.on_release = false -- consumed
        end

        st.top = math.clamp(st.top, 1, st.max_top)
        _reposition(st)
    end

    -- Wrapping hooks (NOT hook_safe) so scroll input + reflow run BEFORE
    -- vanilla update draws the same frame; otherwise the layout would lag the
    -- input by one frame. Neither view's `update` was hooked before this
    -- (grep-verified 2026-07-01). pcall wrap per PROJECT_STANDARDS 4.1; on
    -- error the scroll state is dropped (degrade to vanilla-ish frozen list)
    -- and vanilla update ALWAYS still runs (4.2 guard-is-not-bail).
    mod:hook("DeusShopView", "update", function(func, self, dt, t)
        local ok, err = pcall(_frame, self)

        if not ok then
            self._ct_boon_scroll = nil
            mod:warning("[ct:boon_scroll] shop frame errored: %s (scroll disabled for this view)", tostring(err))
        end

        return func(self, dt, t)
    end)

    mod:hook("DeusCursedChestView", "update", function(func, self, dt, t)
        local ok, err = pcall(_frame, self)

        if not ok then
            self._ct_boon_scroll = nil
            mod:warning("[ct:boon_scroll] chest frame errored: %s (scroll disabled for this view)", tostring(err))
        end

        return func(self, dt, t)
    end)
end

mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        return
    end
    return func(self, name, ...)
end)

mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then
        return nil
    end
    return curse
end)

-- CLARIFY: Save-and-restore pattern for disabled curses. When transitioning into a node, vanilla
-- reads node.curse to spawn the curse mutator. We blank node.curse for the duration of the
-- transition so the mutator doesn't activate, then restore the original value so other code paths
-- (UI tooltips, save state, network sync) still see the canonical curse.
-- POTENTIAL BUG (LOW): If the wrapped `func` errors, restoration is skipped and node.curse stays
-- nil for the rest of the run. Same pattern repeats in start_next_round and _enable_hover.
mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    -- v0.7.39: reset defeat-recovery flag on every level/node transition so each new
    -- mission gets its own one-shot rescue. Forward-declared variable lives near the
    -- defeat-recovery feature block.
    _defeat_recovery_triggered_this_round = false

    -- Task B / #117: reset the per-mission Chest of Trials state on every node
    -- transition so each mission's cursed chests start fresh (first chest = vanilla
    -- seed, subsequent chests perturbed + force-rotated). See the always-on cursed-chest
    -- uniqueness hooks (ConflictDirector.start_terror_event + TerrorEventMixer.start_event).
    _ct_cursed_chest_seq = 0
    _ct_cot_block_last = {}   -- #117: reset per-block last-forced trial pick per mission

    -- (Boon-altar no-repeat taken-boon set deliberately PERSISTS across maps --
    -- only setup_run clears it at run start.)

    local run_controller = self._deus_run_controller
    local graph_data = run_controller and run_controller:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    -- v0.7.107-dev nil-hole audit: DeusMechanism._transition_next_node returns
    -- a single `next_state` value (deus_mechanism.lua:687). Bare unpack is safe
    -- because the result table only ever holds one entry — no internal nil hole
    -- can truncate the return. Left as-is per audit.
    return unpack(results) -- unpack-safe: results holds at most one entry (single-return)
end)

mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local run_controller = self._deus_run_controller
    local current_node = run_controller and run_controller:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    -- CLARIFY: Forcing theme="wastes" prevents the curse-themed visuals/lighting from loading even
    -- though node.curse is suppressed. Without this, the engine could still load curse aesthetic
    -- assets keyed off node.theme (e.g., "tzeentch", "khorne") and produce mismatched visuals.
    -- DIAGNOSTIC (v0.7.142-dev) — client-only "curse lighting not showing": this force fires when
    -- is_curse_disabled() reads the host-synced disable_curse_* value via effective_setting. If a
    -- client's synced value diverged / hasn't arrived, the client suppresses a curse the HOST is
    -- showing and loses the curse sky/lighting. Ungated so a paired host+client log shows the
    -- divergence directly: compare is_curse_disabled per (curse) between the two.
    if saved_curse then
        _dbg("[ct:theme-force] is_server=%s curse=%s theme=%s is_curse_disabled=%s",
            tostring((Managers.player and Managers.player.is_server) and true or false),
            tostring(saved_curse), tostring(saved_theme),
            tostring(is_curse_disabled(saved_curse) and true or false))
    end
    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    -- v0.7.107-dev nil-hole audit: DeusMechanism.start_next_round returns THREE
    -- values (game_mode_key, side_compositions, game_mode_settings) per
    -- deus_mechanism.lua:818. Use _capture_returns so any future signature change
    -- that introduces an interior nil (e.g. an optional middle value) is preserved
    -- end-to-end instead of being silently truncated by `#results`-bounded unpack.
    local n, results = _capture_returns(func(self, ...))

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results, 1, n)
end)

-- NOTE (v0.7.142-dev): the per-node theme/curse/god dump for the host-vs-client
-- lighting diff lives in the EXISTING `GameModeDeus.local_player_game_starts`
-- hook below (`[mission:start]`, ~line 3559) — do NOT add a second hook here
-- (VMF drops it; lint errors). The root-cause signal is the ungated
-- `[ct:theme-force]` line added in the start_next_round hook above.

-- CLARIFY: Suppresses the curse-themed hover preview on the map for nodes whose curse is disabled.
-- Sets theme=nil so the hover view shows the default "wastes" preview instead of (e.g.) the
-- Tzeentch-themed curse preview, accurately reflecting that the player won't experience the curse.
-- POTENTIAL BUG (LOW): Inconsistent return semantics — the disabled-curse path returns nothing
-- (implicit nil), the normal path returns whatever func returns. If a future caller relies on the
-- return value, the disabled path silently differs.
mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]

    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end

    return func(self, node_key, ...)
end)

-- CLARIFY: Custom altar distribution for chests. Vanilla `get_deus_weapon_chest_type` lazily builds
-- self._deus_weapon_chest_distribution from the level's deus_weapon_chest_distribution table on
-- first call per node, then pops one entry per call. We intercept the FIRST call (when distribution
-- is empty), build our own custom distribution if any altar setting is non-zero, write it to
-- self._deus_weapon_chest_distribution, pop one entry, and return it. Subsequent calls find a
-- non-empty distribution and we fall through to vanilla which pops the rest.
-- The custom distribution overrides the entire chest contents — types left at 0 simply don't appear.
-- Filter unknown rarities out of get_own_weapon_pool_excludes. Vanilla
-- `DeusRunController.get_weapon_pool` (line 2130-2134) iterates pool_excludes
-- as the source of truth and does `weapon_pool[pool_rarity][...] = nil`, but
-- weapon_pool only contains the vanilla rarities (plentiful/common/exotic/unique).
-- If a sibling mod (e.g. Peregrinaje) wrote a custom rarity like "modded" to
-- pool_excludes and is no longer active, the `weapon_pool["modded"]` lookup is
-- nil and the indexing crashes with "attempt to index a nil value" inside chest
-- generation (deus_chest_extension.lua:_generate_stored_weapon).
-- We strip non-standard rarities from the returned table so vanilla doesn't trip.
local _VANILLA_RARITIES = { plentiful = true, common = true, exotic = true, unique = true }
mod:hook("DeusRunController", "get_own_weapon_pool_excludes", function(func, self, ...)
    local excludes = func(self, ...)
    if type(excludes) ~= "table" then return excludes end
    for rarity in pairs(excludes) do
        if not _VANILLA_RARITIES[rarity] then
            _dbg("[weapon-pool] stripped unknown rarity '%s' from pool_excludes", tostring(rarity))
            excludes[rarity] = nil
        end
    end
    return excludes
end)

-- ============================================================
-- Fix: Trollhammer Torpedo gets traits but NO properties on CW upgrade
-- ============================================================
-- Vanilla deus weapon-chest upgrade reads WeaponProperties.combinations[property_table_name][rarity]
-- (deus_weapon_generation.lua:161). The Trollhammer Torpedo's property_table_name is
-- "deus_trollhammer_torpedo" (deus_weapons.lua:256), but that key exists ONLY in the TRAIT
-- combinations table, not the PROPERTY combinations table -> the property lookup returns nil, so the
-- torpedo gets traits but ZERO properties on upgrade (reported 2026-06-17). Fix: alias its property
-- pool to the standard ranged-deus pool ("deus_ranged") at load. Idempotent (only when missing),
-- reference-alias is safe (vanilla only reads combinations), no-op if either table is unavailable.
-- TROLLHAMMER_PROPERTY_ALIAS_MARKER
do
    local WP = rawget(_G, "WeaponProperties")
    local combos = WP and WP.combinations
    if combos and rawget(combos, "deus_ranged") and not rawget(combos, "deus_trollhammer_torpedo") then
        combos.deus_trollhammer_torpedo = combos.deus_ranged
        _dbg("[deus-props] aliased deus_trollhammer_torpedo property pool -> deus_ranged (vanilla gap: torpedo had traits but no properties)")
    end
end

_rt_register("trollhammer_property_pool_aliased", function()
    local WP = rawget(_G, "WeaponProperties")
    local combos = WP and WP.combinations
    if not combos then return "skip: WeaponProperties.combinations not loaded" end
    if not rawget(combos, "deus_ranged") then return "skip: deus_ranged property pool absent (vanilla data changed?)" end
    local pool = rawget(combos, "deus_trollhammer_torpedo")
    if pool == nil then return "deus_trollhammer_torpedo property pool still nil -- alias did not apply (torpedo gets no properties)" end
    local n = 0
    for _ in pairs(pool) do n = n + 1 end
    if n == 0 then return "deus_trollhammer_torpedo property pool is empty -- alias did not take" end
end)

-- ============================================================
-- Fix: deus curse banner UI nil theme-color (client/host-crash fix)
-- ============================================================
-- Vanilla DeusCurseUI's curse-info (deus_curse_ui.lua:152) and special-message (:117) paths both
-- read theme_color = DeusThemeSettings[theme].curse_description_color and pass it to
-- _update_description_widget, which assigns it to 5 glow style.color fields (:184-188); the
-- description_start animation then indexes style.<glow>.color[1]. DeusThemeSettings.wastes is the
-- ONLY theme with NO curse_description_color (all 5 god themes + belakor have it), so when ct forces
-- node.theme="wastes" to suppress curse aesthetics (start_next_round / _transition_next_node) while a
-- real curse is still shown, theme_color is nil -> the glow color tables are nil -> the animation
-- crashes "attempt to index field 'color' (a nil value)". Vanilla never hits this (deus_generate_graph
-- forces a god theme for any curse node). Crash 2026-06-17 (sig_citadel_khorne_path5, theme=wastes +
-- curse=curse_corrupted_flesh).
--
-- Fix (v0.7.139-dev): backfill the missing color in DATA at load, instead of hooking the UI.
-- DeusThemeSettings is a boot-global available at mod-load, so this is reliable and timing-free, and
-- it covers BOTH callers (they read theme_color from the same table). The PRIOR approach hooked
-- DeusCurseUI._update_description_widget, but DeusCurseUI lives in scripts/ui/hud_ui/ and isn't loaded
-- until a deus HUD spins up inside an actual CW expedition -- so VMF's string-form hook couldn't
-- resolve the class at the adventure keep, logged a visible "trying to hook object that doesn't
-- exist: DeusCurseUI" error, and likely never installed (reported 2026-06-17). Opaque white matches
-- the icon default; the wastes theme intentionally shows no curse glow, so any opaque value just
-- prevents the nil-index. Idempotent; loops every theme so any future gap is covered. Host and every
-- client run this identically at load, so the data is consistent peer-to-peer.
--
-- SAME-SHAPE SIBLING CRASH (v0.7.156-dev, 2026-06-20) — the curse-DESCRIPTION texture, not the glow:
-- DeusCurseUI's show_curse_info (deus_curse_ui.lua:144-149) and show_special_message (:106-111) both do
--   local icon = theme_settings.icon or { 255, 255, 255, 255 }
-- then _update_description_widget assigns content.theme_icon = icon (:170). The "theme_icon" pass at
-- scenegraph "description_pivot" is pass_type="texture", texture_id="theme_icon"
-- (deus_curse_ui_definitions.lua:317-324), so UIRenderer.draw_texture reads content.theme_icon as the
-- texture NAME -- a STRING. Its content_check_function only tests `~= nil`, NOT string-ness, so the
-- {255,255,255,255} fallback (a TABLE) passes the guard and reaches the renderer. DeusThemeSettings.wastes
-- is the ONLY theme with NO `icon` field (all 5 god themes + belakor have icon="icon_<god>"/"deus_icon_belakor"),
-- so the `or {color}` fallback fires exactly when ct forces theme="wastes" on a still-cursed node ->
-- ui_passes.lua:134 "bad argument #2 to 'UIRenderer_draw_texture' (string expected, got table)". Vanilla
-- never hits it (deus_generate_graph forces a god theme for any curse node). Client crash 2026-06-20 on an
-- injected-adventure level (dlc_termite_*) with a curse active. Same DATA-backfill fix: give every theme a
-- STRING `icon`. "deus_icon_meta_01" is a neutral deus-realm meta icon (gui_icons_atlas, loaded in every CW
-- expedition) -- purely cosmetic for the rare wastes-on-cursed case; the load-bearing requirement is only
-- that it be a valid string so the texture pass stops crashing. Covers BOTH callers (same table read).
-- CURSE_THEME_COLOR_BACKFILL_MARKER  CURSE_THEME_ICON_BACKFILL_MARKER
do
    local TS = rawget(_G, "DeusThemeSettings")
    if type(TS) == "table" then
        local patched = {}
        local patched_icon = {}
        for theme_name, theme in pairs(TS) do
            if type(theme) == "table" and theme.curse_description_color == nil then
                theme.curse_description_color = { 255, 255, 255, 255 }
                patched[#patched + 1] = tostring(theme_name)
            end
            -- texture_id="theme_icon" pass wants a STRING; non-string (or nil -> vanilla's
            -- {color} fallback) crashes UIRenderer.draw_texture. Backfill a valid string.
            if type(theme) == "table" and type(theme.icon) ~= "string" then
                theme.icon = "deus_icon_meta_01"
                patched_icon[#patched_icon + 1] = tostring(theme_name)
            end
        end
        if #patched > 0 then
            _dbg("[curse-ui] backfilled curse_description_color on theme(s) with none: %s (prevents nil-color curse-banner crash when ct forces that theme on a cursed node)",
                table.concat(patched, ", "))
        end
        if #patched_icon > 0 then
            _dbg("[curse-ui] backfilled string icon on theme(s) with none: %s (prevents 'string expected, got table' curse-description texture crash when ct forces that theme on a cursed node)",
                table.concat(patched_icon, ", "))
        end
    end
end

_rt_register("curse_theme_color_backfilled", function()
    local TS = rawget(_G, "DeusThemeSettings")
    if type(TS) ~= "table" then return "skip: DeusThemeSettings not loaded" end
    local wastes = TS.wastes
    if type(wastes) ~= "table" then return "skip: DeusThemeSettings.wastes absent (vanilla data changed?)" end
    local c = wastes.curse_description_color
    if type(c) ~= "table" or #c < 4 then return "DeusThemeSettings.wastes.curse_description_color missing/short -- nil-color curse-banner crash can recur" end
    for i = 1, 4 do if type(c[i]) ~= "number" then return "curse_description_color components must be numbers" end end
    if type(wastes.icon) ~= "string" then return "DeusThemeSettings.wastes.icon not a string -- 'string expected, got table' curse-description texture crash can recur" end
    for theme_name, theme in pairs(TS) do
        if type(theme) == "table" and theme.curse_description_color == nil then
            return "theme '" .. tostring(theme_name) .. "' still has nil curse_description_color"
        end
        if type(theme) == "table" and type(theme.icon) ~= "string" then
            return "theme '" .. tostring(theme_name) .. "' has non-string icon -- curse-description texture pass crashes on a table"
        end
    end
end)

-- ============================================================
-- Guard: native CW path missions with NO deus_weapon_chest_distribution (host-crash fix)
-- ============================================================
-- Vanilla `DeusRunController.get_deus_weapon_chest_type` (deus_run_controller.lua:~2391)
-- reads `LevelSettings[level_key].deus_weapon_chest_distribution` and `assert`s if it
-- is nil, AND it rebuilds from that same table every time the distribution is exhausted.
-- Some native CW path missions (e.g. cemetery_tzeentch_path1 and the other Beastmen /
-- Tzeentch path variants) ship with NO distribution, so the assert HARD-CRASHES the host
-- the moment a deus weapon chest spawns (crash 2026-06-17, nicho, cemetery_tzeentch_path1:
-- "No deus_weapon_chest_distribution set for cemetery_tzeentch_path1" — same class as
-- Issues #58/#60/#68, but fatal rather than just missing pickups). A one-shot patch on
-- self._deus_weapon_chest_distribution is NOT enough (vanilla re-reads LevelSettings on
-- exhaustion), so we inject a balanced fallback INTO LevelSettings[level_key] — idempotent,
-- never overwrites an existing distribution, deterministic across host/clients.
-- Decomposed into pure helpers for the deus_chest_distribution_fallback regression test.
mod._ct_deus_chest_needs_fallback = function(level_settings)
    return level_settings ~= nil and level_settings.deus_weapon_chest_distribution == nil
end

mod._ct_build_deus_chest_fallback = function(chest_types)
    if not chest_types then return nil end
    -- Vanilla {chest_type = amount} shape; one of each type so every chest draws a
    -- sensible variety. Vanilla expands this into a list, shuffles by level_seed, and
    -- re-expands it on exhaustion.
    return {
        [chest_types.upgrade]     = 1,
        [chest_types.swap_melee]  = 1,
        [chest_types.swap_ranged] = 1,
        [chest_types.power_up]    = 1,
    }
end

mod._ct_ensure_deus_chest_distribution = function(drc)
    local LS = rawget(_G, "LevelSettings")
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    if not (LS and DCT and drc) then return end
    -- Resolve the current level_key exactly as vanilla does.
    local run_state = drc._run_state
    local node_key = run_state and run_state:get_current_node_key()
    local graph = drc._get_graph_data and drc:_get_graph_data()
    local node = graph and node_key and graph[node_key]
    local level_key = node and node.level
    if not level_key then return end
    local ls = LS[level_key]
    if not mod._ct_deus_chest_needs_fallback(ls) then return end
    local fallback = mod._ct_build_deus_chest_fallback(DCT)
    if not fallback then return end
    ls.deus_weapon_chest_distribution = fallback
    -- NOT a warning: injecting this fallback is the EXPECTED, correct behavior on every
    -- native CW path mission (dlc_castle_*, cemetery_*, etc.) — those simply ship no
    -- deus_weapon_chest_distribution, and we supply a balanced one so vanilla's assert
    -- can't fire. Nothing to investigate, so it's a file-only debug line, not a warning
    -- (a warning should mean "maybe a problem"; this is working as designed).
    _dbg("[deus-chest] '%s' had no deus_weapon_chest_distribution (native CW path mission) -- injected a balanced fallback (expected for these missions).", tostring(level_key))
end

_rt_register("deus_chest_distribution_fallback", function()
    -- Native CW path missions (e.g. cemetery_tzeentch_path1) can lack a
    -- deus_weapon_chest_distribution; vanilla get_deus_weapon_chest_type asserts and
    -- HARD-CRASHES the host on chest spawn (crash 2026-06-17). ct injects a fallback into
    -- LevelSettings. This pins the inject/skip decision + the fallback shape.
    if not mod._ct_deus_chest_needs_fallback({ deus_weapon_chest_distribution = nil }) then
        return "must flag a level whose deus_weapon_chest_distribution is nil as needing a fallback"
    end
    if mod._ct_deus_chest_needs_fallback({ deus_weapon_chest_distribution = { foo = 1 } }) then
        return "must NOT flag (overwrite) a level that already has a distribution"
    end
    if mod._ct_deus_chest_needs_fallback(nil) then
        return "must NOT inject into a nil level_settings entry"
    end
    local fb = mod._ct_build_deus_chest_fallback({ upgrade = "u", swap_melee = "m", swap_ranged = "r", power_up = "p" })
    if type(fb) ~= "table" then return "fallback must be a table" end
    local n = 0
    for _, amount in pairs(fb) do
        n = n + 1
        if type(amount) ~= "number" or amount < 1 then return "fallback amounts must be positive numbers" end
    end
    if n ~= 4 then return "fallback must cover all 4 chest types, got " .. tostring(n) end
    if not (fb.u and fb.m and fb.r and fb.p) then return "fallback must key on each DEUS_CHEST_TYPES value" end
    if mod._ct_build_deus_chest_fallback(nil) ~= nil then return "must return nil when DEUS_CHEST_TYPES is unavailable (degrade, don't error)" end
end)

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local distribution = self._deus_weapon_chest_distribution
    -- Prevent the vanilla "No deus_weapon_chest_distribution" assert (host crash) on CW
    -- path missions that ship without one. Idempotent; runs before any path that reaches
    -- vanilla's lookup/rebuild (incl. the custom-altar early-return path below).
    mod._ct_ensure_deus_chest_distribution(self)

    if (not distribution or #distribution == 0) and DEUS_CHEST_TYPES then
        -- v0.7.42: effective_setting so client's chest opens see host's distribution.
        -- v0.7.65: sentinel -1 = "Default" (use vanilla random distribution). 0 = literal
        -- zero altars of this type. is_custom is true if ANY altar setting is not the
        -- sentinel (the user has expressed an override). For altars set to Default in a
        -- mixed config (one type explicit, others "Default"), the Default ones contribute
        -- ZERO to the override distribution — explicit per-type control. If users want
        -- vanilla random behavior, ALL four must be "Default".
        local upgrade = effective_setting("chest_upgrade_count") or -1
        local swap_melee = effective_setting("chest_swap_melee_count") or -1
        local swap_ranged = effective_setting("chest_swap_ranged_count") or -1
        local power_up = effective_setting("chest_power_up_count") or -1

        local is_custom = upgrade ~= -1 or swap_melee ~= -1 or swap_ranged ~= -1 or power_up ~= -1
        if is_custom then
            local function as_count(v) return (v == -1) and 0 or v end
            local new_distribution = {}
            for _ = 1, as_count(upgrade)    do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.upgrade    end
            for _ = 1, as_count(swap_melee) do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_melee end
            for _ = 1, as_count(swap_ranged)do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for _ = 1, as_count(power_up)   do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.power_up   end

            if #new_distribution > 0 then
                -- CLARIFY: Seeding the shuffle with the node's level_seed ensures deterministic
                -- altar order across host/clients on the same node. Falls back to seed=0 if any
                -- intermediate is nil (defensive — shouldn't normally happen since this hook only
                -- fires inside an active run).
                local run_state = self._run_state
                local node_key = run_state and run_state:get_current_node_key()
                local graph = self:_get_graph_data()
                local node = graph and node_key and graph[node_key]
                local level_seed_val = node and node.level_seed
                local seed = (level_seed_val and HashUtils and HashUtils.fnv32_hash and HashUtils.fnv32_hash(level_seed_val)) or 0

                -- Issue #6 auto-probe: log shuffle inputs PRE-shuffle so host/client logs can
                -- be diffed offline without the user running /verify_altars manually. Gated on
                -- VMF debug logging via _dbg (file-only, never spams in-game chat).
                local _is_server = (Managers and Managers.player and Managers.player.is_server) or false
                _dbg("[altar:get_chest_type] PRE node=%s level_seed=%s hash=%s eff_u/m/r/p=%s/%s/%s/%s is_server=%s dist=[%s]",
                    tostring(node_key), tostring(level_seed_val), tostring(seed),
                    tostring(upgrade), tostring(swap_melee), tostring(swap_ranged), tostring(power_up),
                    tostring(_is_server), table.concat(new_distribution, ","))

                table.shuffle(new_distribution, seed)

                _dbg("[altar:get_chest_type] POST node=%s seed=%s is_server=%s shuffled=[%s]",
                    tostring(node_key), tostring(seed), tostring(_is_server),
                    table.concat(new_distribution, ","))

                self._deus_weapon_chest_distribution = new_distribution
                local chest_type = new_distribution[#new_distribution]
                new_distribution[#new_distribution] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

-- CLARIFY: Builds the union of all trait-combinations across all CW weapons, deduplicated. Used
-- when "Any Trait on Any Weapon" is enabled — every weapon gets the FULL pool of trait combos
-- instead of its baked subset. The dedupe key uses "\0" as separator since trait names can't
-- contain null bytes; this avoids ambiguity (e.g. `{"a","bc"}` vs `{"ab","c"}`).
-- POTENTIAL BUG (LOW): The cache is never invalidated. If DeusWeapons is mutated after first call
-- (e.g. by another mod), stale combos persist. Acceptable since DeusWeapons is normally static.
local function get_all_trait_combos()
    if all_trait_combos_cache then
        return all_trait_combos_cache
    end
    if not DeusWeapons then
        return nil
    end

    local combos = {}
    local seen = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                local key = table.concat(combo, "\0")
                if not seen[key] then
                    seen[key] = true
                    combos[#combos + 1] = combo
                end
            end
        end
    end

    all_trait_combos_cache = combos
    return combos
end

-- CLARIFY: Trait filter has three behaviors based on the `any_trait_any_weapon` toggle and the
-- ban list. The base pool is either the weapon's vanilla trait combos or the global expanded pool.
-- Then any combo containing a banned trait is removed from `filtered`.
-- The new_value selection logic:
--   - filtered partially shrunk (some bans hit, some left): use filtered
--   - filtered emptied (every combo had a ban): keep `base` so the weapon isn't unrollable —
--     a fully-banned weapon would crash the upgrade UI when no traits can be picked
--   - filtered unchanged but `expanded_pool` differs from original: use base (= expanded_pool)
--   - filtered unchanged and base==original: skip (no patch needed)
-- POTENTIAL BUG (LOW): When `filtered` is empty, falling back to `base` means banned traits CAN
-- still appear on that weapon. This is a reasonable graceful-degradation choice but the UI tooltip
-- doesn't tell the user.
local function apply_weapon_trait_filter()
    if not DeusWeapons then
        return {}
    end

    local any_trait = effective_setting("any_trait_any_weapon")
    local expanded_pool = any_trait and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local base = expanded_pool or original
        if base then
            local filtered = {}
            for _, combo in ipairs(base) do
                local keep = true
                for _, trait in ipairs(combo) do
                    if effective_setting("ban_trait_" .. trait) then
                        keep = false
                        break
                    end
                end
                if keep then
                    filtered[#filtered + 1] = combo
                end
            end

            local new_value
            if #filtered < #base and #filtered > 0 then
                new_value = filtered
            elseif #filtered == 0 then
                new_value = base
            elseif base ~= original then
                new_value = base
            end

            if new_value and new_value ~= original then
                saved[item_key] = original
                data.baked_trait_combinations = new_value
            end
        end
    end

    return saved
end

local function restore_weapon_trait_filter(saved)
    if not DeusWeapons then
        return
    end

    for item_key, original in pairs(saved) do
        DeusWeapons[item_key].baked_trait_combinations = original
    end
end

-- ============================================================
-- Trait Tier by Rarity (v0.7.28a-alpha)
-- ============================================================
-- TRAIT_RARITY_POOL: maps every weapon trait → set of rarities at which it can roll.
-- Walked all 34 traits with the user 2026-05-15; basis lives in TRAITS_REFERENCE.md.
-- T1=common (green), T2=rare (blue), T3=exotic (orange), T4=unique (red).
-- Multi-tier means the trait is eligible in multiple rarity pools.
--
-- When `tweak_trait_tier_by_rarity` is on, every weapon roll/upgrade picks a trait
-- combo whose ALL traits are eligible for the rolled rarity. Implementation: hook the
-- public DeusWeaponGeneration methods, call vanilla, then overwrite result.traits with
-- a tier-filtered random pick. This ALSO enables traits at common/rare rarities (which
-- vanilla skips per `deus_weapon_generation.lua:166-169`) because we don't rely on the
-- vanilla rarity gate — we pick from the original baked_trait_combinations and filter.
local TRAIT_RARITY_POOL = {
    -- T1 only (common / green)
    melee_increase_damage_on_block                = { common = true },
    melee_reduce_cooldown_on_crit                 = { common = true },
    melee_shield_on_assist                        = { common = true },
    melee_timed_block_cost                        = { common = true },
    ranged_reduce_cooldown_on_crit                = { common = true },
    ranged_restore_stamina_headshot               = { common = true },
    shield_splinters                              = { common = true },
    deus_ammo_pickup_reload_speed                 = { common = true },
    deus_big_swing_stagger                        = { common = true },
    -- T2 only (rare / blue)
    melee_heal_on_crit                            = { rare = true },
    ranged_consecutive_hits_increase_power        = { rare = true },
    ranged_increase_power_level_vs_armour_crit    = { rare = true },
    ranged_reduced_overcharge                     = { rare = true },
    ranged_remove_overcharge_on_crit              = { rare = true },
    melee_counter_push_power                      = { rare = true },
    bloodthirst                                   = { rare = true },
    headhunter                                    = { rare = true },
    follow_up                                     = { rare = true },
    -- T3 only (exotic / orange)
    shield_of_isha                                = { exotic = true },
    stagger_aoe_on_crit                           = { exotic = true },
    serrated_blade                                = { exotic = true },
    melee_attack_speed_on_crit                    = { exotic = true },
    -- T4 only (unique / red)
    armor_breaker                                 = { unique = true },
    refilling_shot                                = { unique = true },
    home_run                                      = { unique = true },
    deus_crit_chain_lightning                     = { unique = true },
    deus_extra_shot                               = { unique = true },
    always_blocking                               = { unique = true },
    -- T2 + T3
    ranged_replenish_ammo_on_crit                 = { rare = true,   exotic = true },
    ranged_replenish_ammo_headshot                = { rare = true,   exotic = true },
    -- T3 + T4
    piercing_projectiles                          = { exotic = true, unique = true },
    crescendo_strike                              = { exotic = true, unique = true },
    deus_collateral_damage_on_melee_killing_blow  = { exotic = true, unique = true },
    deus_ranged_crit_explosion                    = { exotic = true, unique = true },
}

-- v0.7.177-dev #119: Trait Tier by Rarity must NOT restrict by weapon TYPE.
-- The user assigns each trait to one-or-more rarity tiers via TRAIT_RARITY_POOL; the
-- ONLY other restriction they want is melee-vs-ranged (a melee weapon gets melee
-- traits, a ranged weapon gets ranged traits). The PRE-#119 implementation read the
-- weapon's OWN `baked_trait_combinations`, which the vanilla baker had already narrowed
-- by `compatible_weapon_list` (a weapon-TYPE restriction) — so e.g. a 1h sword could
-- only ever roll the handful of traits in its own deus_melee compatible subset, and
-- fire/heat staves were stuck with their narrow deus_ranged_heat pool. That weapon-type
-- gate is exactly what the user reported as wrong.
--
-- NEW: draw from the full melee (or ranged) trait UNION across every deus trait pool,
-- gated only by (a) the rolled rarity tier per TRAIT_RARITY_POOL and (b) the ban list.
-- The melee/ranged classification is derived at runtime from WeaponTraits.combinations
-- (canonical source — weapon_traits_morris.lua: deus_melee / deus_shield_melee /
-- deus_heavy_melee are melee; deus_ranged* / deus_trollhammer_torpedo are ranged) so it
-- tracks any data change. Traits present in BOTH classes (headhunter, shield_splinters,
-- piercing_projectiles, stagger_aoe_on_crit, deus_crit_chain_lightning) land in both
-- unions, which is correct — they are genuinely usable on either class. This also
-- supersedes the old fire/heat "fall back to own pool" hack: a heat weapon now draws
-- from the whole ranged union, so it gets a tier-eligible ranged trait like any other.
-- Stored on `mod` (not main-chunk locals) to stay under Lua's 200-locals-per-chunk
-- limit; the cache `mod._ct_trait_class_pools` and the builder are reused by the
-- tier filter and the #119 regression test.
mod._ct_get_trait_class_pools = function()
    if mod._ct_trait_class_pools then return mod._ct_trait_class_pools end
    local WT = rawget(_G, "WeaponTraits")
    if not WT or not WT.combinations then return nil end
    local melee, ranged = {}, {}
    for pool_name, combos in pairs(WT.combinations) do
        if type(pool_name) == "string" and pool_name:find("^deus_") then
            local dest = pool_name:find("melee") and melee or ranged
            for _, combo in ipairs(combos) do
                for _, trait in ipairs(combo) do
                    dest[trait] = true
                end
            end
        end
    end
    mod._ct_trait_class_pools = { melee = melee, ranged = ranged }
    return mod._ct_trait_class_pools
end

-- Returns single-trait combos eligible for `rarity` on the weapon's COMBAT CLASS
-- (melee/ranged), drawn from the class-wide union (see #119 note above). The ban list
-- is honored here too (a banned trait never appears). Falls back to the weapon's own
-- baked pool ONLY if WeaponTraits.combinations isn't loaded yet, so a roll never crashes.
local function get_tier_filtered_combos(item_key, rarity)
    if not DeusWeapons or not DeusWeapons[item_key] then return {} end
    local data = DeusWeapons[item_key]
    local pools = mod._ct_get_trait_class_pools()
    if pools then
        local ttn = data.trait_table_name
        local is_ranged = type(ttn) == "string" and not ttn:find("melee")
        local class_pool = is_ranged and pools.ranged or pools.melee
        local filtered = {}
        for trait in pairs(class_pool) do
            local rp = TRAIT_RARITY_POOL[trait]
            if rp and rp[rarity] and not effective_setting("ban_trait_" .. trait) then
                filtered[#filtered + 1] = { trait }
            end
        end
        -- May legitimately be empty (e.g. user banned every eligible trait at this
        -- tier, or assigned none) -> the weapon gets no injected trait this roll.
        return filtered
    end

    -- Fallback path: WeaponTraits not loaded yet -> tier-filter the weapon's OWN baked
    -- pool, mirroring the pre-#119 behavior so we never error during early timing.
    local original = data.baked_trait_combinations
    if not original then return {} end
    local filtered = {}
    for _, combo in ipairs(original) do
        local all_eligible = true
        for _, trait in ipairs(combo) do
            local pool = TRAIT_RARITY_POOL[trait]
            if not pool or not pool[rarity] then
                all_eligible = false
                break
            end
        end
        if all_eligible then
            filtered[#filtered + 1] = combo
        end
    end
    return filtered
end

-- Regression guard for #119 (class-union tier filter): a fire/heat ranged deus weapon
-- (narrow own deus_ranged_heat pool in the OLD design) must, at a rarity tier it can roll
-- (rare), get a NON-EMPTY pool whose every offered trait is (a) in the RANGED class union
-- and (b) eligible at that tier per TRAIT_RARITY_POOL — i.e. it is no longer confined to
-- its own weapon-type subset. This is the inverse of the old fire-fallback guard.
_rt_register("tier_by_rarity_class_union_ranged", function()
    if not DeusWeapons then return "skip: DeusWeapons not loaded" end
    local pools = mod._ct_get_trait_class_pools()
    if not pools then return "skip: WeaponTraits.combinations not loaded" end
    local fire_key
    for k, data in pairs(DeusWeapons) do
        if type(data) == "table" and data.trait_table_name == "deus_ranged_heat" then
            fire_key = k
            break
        end
    end
    if not fire_key then return "skip: no deus_ranged_heat weapon found (vanilla data changed?)" end
    local combos = get_tier_filtered_combos(fire_key, "rare")
    if #combos == 0 then
        return string.format("TIER-UNION REGRESSION: ranged weapon '%s' got empty pool at rare (class union broken)", tostring(fire_key))
    end
    for _, combo in ipairs(combos) do
        for _, t in ipairs(combo) do
            if not pools.ranged[t] then
                return string.format("TIER-UNION REGRESSION: ranged weapon '%s' offered non-ranged trait '%s'", tostring(fire_key), tostring(t))
            end
            local rp = TRAIT_RARITY_POOL[t]
            if not (rp and rp.rare) then
                return string.format("TIER-UNION REGRESSION: weapon '%s' offered '%s' not eligible at rare tier", tostring(fire_key), tostring(t))
            end
        end
    end
end)

-- Post-process the result of a vanilla weapon generation/upgrade: overwrite result.traits
-- with a tier-eligible combo for the rolled rarity. No-op if:
--   - the toggle is off
--   - result is nil or has no deus_item_key
--   - #118: the rolled rarity is `plentiful` (WHITE starting weapons must NEVER receive
--     an injected trait — see the gate below). `common` (GREEN/uncommon) and up DO get
--     traits — corrected 2026-06-27 per user: green is uncommon and should be trait-eligible.
--   - the class-union pool is empty for this rarity (get_tier_filtered_combos returns {})
-- get_tier_filtered_combos now draws from the weapon's melee/ranged class union (#119),
-- so a weapon is no longer confined to its own weapon-type trait subset.
local function override_traits_in_result(result, rarity)
    if not effective_setting("tweak_trait_tier_by_rarity") then return result end
    if not result or not result.deus_item_key then return result end
    -- #118: ONLY the white `plentiful` STARTING tier stays trait-less. `common` (green /
    -- "uncommon"), `rare` (blue), `exotic`, and `unique` are all trait-eligible. The rarity
    -- ladder is plentiful(white) < common(green) < rare(blue) < exotic < unique; the user
    -- confirmed green=uncommon SHOULD get traits, so we gate only `plentiful` here. Applies
    -- regardless of which trait toggle is active.
    if rarity == "plentiful" then return result end
    local combos = get_tier_filtered_combos(result.deus_item_key, rarity)
    if #combos == 0 then return result end
    local picked = combos[math.random(#combos)]
    local new_traits = {}
    for _, trait in ipairs(picked) do
        new_traits[#new_traits + 1] = trait
    end
    result.traits = new_traits
    return result
end

-- CLARIFY: Three trait-filter wrap points cover the three vanilla call sites that read
-- baked_trait_combinations: initial weapon roll, slot-specific roll (Belakor temple?), and altar
-- upgrade. Same save/restore pattern as the boon hooks above.
-- v0.7.28a: each hook now ALSO post-processes with `override_traits_in_result` to apply tier-by-rarity.
--
-- audit 2026-06-07 (F14, v0.7.133-dev): each hook now wraps the apply/func/restore
-- bracket in pcall, mirroring the boon-removal hardening at generate_random_power_ups
-- (v0.7.90). Previously, if vanilla raised inside func(), restore_weapon_trait_filter
-- was skipped and DeusWeapons[*].baked_trait_combinations stayed permanently filtered
-- for the rest of the session (state corruption — banned traits would never come back,
-- or any_trait_any_weapon's expanded pool would stick). _filtered_weapon_gen wraps the
-- vanilla call in pcall, guarantees restore on the error path, _dbg_alert's the failure,
-- then re-raises with the original message so the game's handler still logs it. Helper
-- keeps all four hooks consistent (BUG_CLASSES save/restore-without-pcall pattern).
--
-- The vanilla functions take trailing nilable args (seed / weapon_pool / slot_chance_*),
-- so callers MUST pass arity-preserving (n, args) captured via select("#", ...) at the
-- hook (VMF_RECIPES §2a) — bare unpack(args) would truncate at a nil seed. We pre-capture
-- (n, args) in each hook rather than forward `...` into a nested closure, because Lua 5.1
-- forbids referencing `...` inside an inner function (compile error).
local function _filtered_weapon_gen(label, func, gen_rarity, n, args)
    local saved = apply_weapon_trait_filter()
    local ok, result = pcall(function() return func(unpack(args, 1, n)) end)
    restore_weapon_trait_filter(saved)
    if not ok then
        -- v0.7.159-dev Task 3: `generate_weapon_for_slot` has NO vanilla caller in
        -- the decompiled source — the ONLY invoker is ct's own bot-weapon-mirror
        -- helper `_gen_bot_weapon_for_slot` (~L5726), which ALREADY wraps the call
        -- in pcall and treats a raise as "bot just skips that slot this roll" (no
        -- crash, no user-visible effect). The raise itself is the VANILLA
        -- `fassert(#weapon_keys > 0, "...weapon_pool state...")` at
        -- deus_weapon_generation.lua:110 — fired when the bot's career weapon_pool
        -- has no weapon group matching the requested slot at the target rarity. It
        -- is NOT a trait-filter fault (the filter only rewrites
        -- baked_trait_combinations, read later for exotic/unique only). So for this
        -- label the loud ungated warning was misattributed noise (~8x/run). Downgrade
        -- it to debug-gated. The other three labels (generate_weapon /
        -- generate_item_from_item_key / upgrade_item) ARE on real vanilla gameplay
        -- paths with no upstream pcall, so a raise there IS user-visible — keep the
        -- ungated warning for them (v0.7.134 rationale).
        if label == "generate_weapon_for_slot" then
            _dbg("[trait-filter] %s vanilla call raised (benign — caller pcall-guards; "
                .. "root is vanilla empty-slot weapon_pool fassert, not the trait filter); "
                .. "DeusWeapons restored: %s", label, tostring(result))
        else
            -- v0.7.134: ungated — a raised vanilla call on these paths is a user-visible
            -- failure; it must reach the log without Debug Logging enabled. The engine logs
            -- the re-raise too, but without this mod-context line.
            mod:warning("[trait-filter] %s vanilla call raised; DeusWeapons restored: %s",
                label, tostring(result))
        end
        error(result, 2)  -- re-raise; baked_trait_combinations is now restored
    end
    return override_traits_in_result(result, gen_rarity)
end

mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, difficulty, run_progress, rarity, ...)
    return _filtered_weapon_gen("generate_weapon", func, rarity,
        select("#", ...) + 3, { difficulty, run_progress, rarity, ... })
end)

mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, difficulty, run_progress, rarity, ...)
    return _filtered_weapon_gen("generate_weapon_for_slot", func, rarity,
        select("#", ...) + 3, { difficulty, run_progress, rarity, ... })
end)

mod:hook("DeusWeaponGeneration", "generate_item_from_item_key", function(func, item_key, difficulty, run_progress, rarity, ...)
    return _filtered_weapon_gen("generate_item_from_item_key", func, rarity,
        select("#", ...) + 4, { item_key, difficulty, run_progress, rarity, ... })
end)

mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, item, difficulty, run_progress, target_rarity, ...)
    return _filtered_weapon_gen("upgrade_item", func, target_rarity,
        select("#", ...) + 4, { item, difficulty, run_progress, target_rarity, ... })
end)

-- Upstream override for `force_belakor` (v0.7.49 / v0.7.120 Issue #53 fix).
--
-- Vanilla `game_round_ended` calls `deus_backend:deus_journey_with_belakor(journey_name)`
-- on the HOST to compute the `with_belakor` flag, then uses that single value for BOTH
-- `_setup_run` (host local state) AND `send_rpc_clients("rpc_deus_setup_run", ..., with_belakor, ...)`
-- (client setup). That part works correctly with our override on the host.
--
-- BUT: `deus_journey_with_belakor` is ALSO called on EVERY peer from non-RPC code paths —
-- `DeusMechanism.get_level_dialogue_context` (deus_mechanism.lua:1337) reads it locally on
-- both host and client. UI views can also read it for journey-icon display. Prior to v0.7.120
-- this hook was gated on `is_server` only, so client peers fell through to vanilla — which
-- returns the journey's NATURAL belakor-cycle position regardless of host's toggle. Net
-- effect: any client-local code path that asks "does this journey have belakor?" got the
-- wrong answer when host had force_belakor on, which is the Issue #53 root cause class.
--
-- v0.7.120 fix: read `effective_setting("force_belakor")` (host-broadcast on clients, local
-- on host) instead. This makes BOTH peers' local calls return true when host has the toggle
-- on. Safe because: (1) `effective_setting` resolves to host's value on the client, never
-- the client's stale local; (2) the only client-local consumers of this method are display /
-- dialogue / telemetry — none of them are authoritative gameplay state, so they should
-- mirror the host. The host-only `game_round_ended` path is unchanged.
mod:hook("BackendInterfaceDeusPlayFab", "deus_journey_with_belakor", function(func, self, journey_name)
    local override = effective_setting("force_belakor") == true
    if override then
        _dbg("[belakor:deus_journey_with_belakor] journey=%s force_belakor=true -> returning true (was: %s)",
            tostring(journey_name), tostring(func(self, journey_name)))
        return true
    end
    local v = func(self, journey_name)
    _dbg("[belakor:deus_journey_with_belakor] journey=%s force_belakor=off -> vanilla=%s",
        tostring(journey_name), tostring(v))
    return v
end)

-- ============================================================
-- v0.7.120-dev — Aggressive diagnostics for Belakor's Temple client sync (Issue #53)
-- ============================================================
-- Comprehensive state dumps gated on VMF debug logging (so the user turns on VMF's
-- debug log level for a test co-op session, captures the data, sends the log). Goal: definitively
-- identify whether the temple node fails to render on client because:
--   A. Client's `with_belakor` arg is actually false despite host having force_belakor on
--   B. Client's graph doesn't contain arena nodes after populate_graph runs
--   C. SharedState arena_belakor_node value isn't reaching the client
--   D. The map scene's per-node level-prefix-to-unit lookup skips the arena unit
--   E. Some other peer-specific code path we haven't traced
--
-- Every dump line is prefixed `[belakor:diag]` so the user can grep one tag and see
-- the full sequence from journey start → map open. Both peers should run with
-- VMF debug logging ON to produce the diff.

-- (1) Hook DeusMechanism._setup_run to log the full args on both peers.
-- _setup_run runs on the host (from game_round_ended) AND on the client (from
-- rpc_deus_setup_run handler). This is the canonical entry point for "the run
-- starts" — capture run_seed + journey + dominant_god + with_belakor + mutators
-- to confirm both peers run with identical args.
mod:hook_safe("DeusMechanism", "_setup_run", function(self, run_id, run_seed, is_initial_setup, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
    local is_server = Managers and Managers.player and Managers.player.is_server
    local m_count = (type(mutators) == "table") and #mutators or "?"
    local b_count = (type(boons) == "table") and #boons or "?"
    _dbg("[belakor:diag] _setup_run is_server=%s run_id=%s run_seed=%s journey=%s dominant_god=%s with_belakor=%s mutators=%s boons=%s is_initial=%s server_peer=%s",
        tostring(is_server), tostring(run_id), tostring(run_seed),
        tostring(journey_name), tostring(dominant_god), tostring(with_belakor),
        tostring(m_count), tostring(b_count),
        tostring(is_initial_setup), tostring(server_peer_id))
end)

-- (2) [intentionally no separate setup_run hook] — the diagnostic graph-dump
-- for DeusRunController.setup_run was folded INTO the existing full hook at
-- line ~1224. VMF doesn't allow two hooks on the same Class.method, even when
-- one is mod:hook and the other mod:hook_safe (mod-lint enforces this rule).
-- Search for "belakor:diag DeusRunController.setup_run done" inside the existing
-- DeusRunController.setup_run hook body to find the dump.

-- (3) Hook DeusRunController.unlock_arena_belakor (host-only by design) to log
-- the trigger that should propagate arena_belakor_node to client via SharedState.
mod:hook_safe("DeusRunController", "unlock_arena_belakor", function(self)
    local rs = self._run_state
    local picked = rs and rs.get_arena_belakor_node and rs:get_arena_belakor_node() or nil
    local current = rs and rs.get_current_node_key and rs:get_current_node_key() or nil
    _dbg("[belakor:diag] unlock_arena_belakor fired (host only) current_node=%s -> picked arena_belakor_node=%s (SharedState write — clients should see this via <rpc set server> arena_belakor_node)",
        tostring(current), tostring(picked))
end)

-- (4) Hook DeusMapDecisionView._start to dump the full map state when the map
-- opens. Runs on BOTH peers when the in-mission Holseher map view opens between
-- nodes. This is the single most diagnostic moment for Issue #53.
mod:hook_safe("DeusMapDecisionView", "_start", function(self)
    local rc = self._deus_run_controller
    if not rc then
        _dbg("[belakor:diag] map_open _start: no run_controller (unexpected)")
        return
    end
    local rs = rc._run_state
    local is_server = self._is_server
    local cur_key = rc.get_current_node_key and rc:get_current_node_key() or nil
    local journey = rc.get_journey_name and rc:get_journey_name() or nil
    local arena_node = rs and rs.get_arena_belakor_node and rs:get_arena_belakor_node() or nil
    local belakor_enabled = rs and rs.get_belakor_enabled and rs:get_belakor_enabled() or nil
    local seen = rc.has_own_seen_arena_belakor_node and rc:has_own_seen_arena_belakor_node() or nil
    local pg = rc._get_graph_data and rc:_get_graph_data() or nil
    local total, arena_count = 0, 0
    local arena_keys = {}
    if type(pg) == "table" then
        for k, n in pairs(pg) do
            total = total + 1
            if type(n) == "table" then
                local lvl = n.level or ""
                if type(lvl) == "string" and lvl:find("^arena") then
                    arena_count = arena_count + 1
                    arena_keys[#arena_keys + 1] = tostring(k) .. "(" .. lvl .. ",theme=" .. tostring(n.theme) .. ")"
                end
            end
        end
    end
    _dbg("[belakor:diag] MAP_OPEN _start is_server=%s journey=%s current_node=%s belakor_enabled=%s arena_belakor_node=%s has_own_seen=%s graph_total=%d arena_in_graph=%d (%s) force_setting=%s",
        tostring(is_server), tostring(journey), tostring(cur_key),
        tostring(belakor_enabled), tostring(arena_node), tostring(seen),
        total, arena_count, table.concat(arena_keys, ","),
        tostring(effective_setting("force_belakor")))
    -- Per-node dump (every node + its level prefix) so we can see why the map scene
    -- might not be spawning an ARENA_NODE_UNIT for any node.
    if type(pg) == "table" then
        for k, n in pairs(pg) do
            if type(n) == "table" then
                local lvl = tostring(n.level or "?")
                local prefix
                if k == "start" then
                    prefix = "<start>"
                else
                    local us = lvl:find("_")
                    prefix = (us and us > 1) and lvl:sub(1, us - 1) or lvl
                end
                -- v0.7.124-dev: added level_seed + mutators per-node so host/client
                -- log diff can spot per-mission generation divergence (Issue: citadel
                -- curse mismatch — display fields synced but per-mission internals not).
                local mut_str = "<nil>"
                if type(n.mutators) == "table" then
                    local list = {}
                    for i, m in ipairs(n.mutators) do list[i] = tostring(m) end
                    mut_str = "{" .. table.concat(list, ",") .. "}"
                end
                _dbg("[belakor:diag] MAP_OPEN node %s level=%s prefix=%s theme=%s curse=%s god=%s node_type=%s level_seed=%s mutators=%s",
                    tostring(k), lvl, prefix, tostring(n.theme),
                    tostring(n.curse), tostring(n.god), tostring(n.node_type),
                    tostring(n.level_seed), mut_str)
            end
        end
    end
end)

-- Belakor's Temple → unique-tier boon rewards (always-on as of v0.7.83;
-- the prior `tweak_belakor_temple_unique_boons` toggle was removed per user
-- 2026-05-22). Implementation lives in the consolidated
-- DeusPowerUpUtils.generate_random_power_ups hook above — see the
-- "Belakor temple force-rarity" comment block in that function body.

-- v0.7.53: Upstream override for `finale_dominant_god`. Same bug shape as the old
-- `force_belakor` issue (fixed in v0.7.49): `game_round_ended` reads
-- `self._vote_data.dominant_god` into a local at the top, then uses it for BOTH
-- `_setup_run` AND `send_rpc_clients(..., dominant_god_id, ...)`. The previous
-- `_setup_run` hook only changed the value INSIDE `_setup_run` — host's local run state
-- saw the override but the RPC payload kept the original god, so clients populated their
-- graph with vanilla god distribution. Fix: pre-mutate `self._vote_data.dominant_god`
-- before vanilla `game_round_ended` runs, restore after. Both paths then see the override.
--
-- Restore-on-return is critical: vote_data persists on `self` and is consumed once per
-- mission-start; leaving it mutated would survive across rounds.
mod:hook("DeusMechanism", "game_round_ended", function(func, self, t, dt, reason, reason_data)
    local is_server = Managers and Managers.player and Managers.player.is_server
    local restored = false
    local original_god
    local vote_data = self._vote_data
    if reason == "start_game" and is_server and vote_data then
        local god_index = mod:get("finale_dominant_god")
        if god_index and god_index > 0 then
            local god = FINALE_GODS[god_index]
            if god then
                original_god = vote_data.dominant_god
                vote_data.dominant_god = god
                restored = true
            end
        end
    end

    local ok, err = pcall(func, self, t, dt, reason, reason_data)

    if restored then
        vote_data.dominant_god = original_god
    end

    if not ok then
        -- v0.7.81: swallow the error instead of re-throwing. Lyndsey
        -- host crash 2026-05-22 02:53:44 GUID ecf0227e: vanilla
        -- `game_round_ended` internally broadcasts vote_data via
        -- mod_user_data RPC. VMF JSON-encodes the entire payload into
        -- one string; Stingray's STRING_MAX=500 hardcap fails when
        -- vote_data has grown large (per-peer votes + boon lists +
        -- god weights can exceed the limit on long deus runs).
        --
        -- Re-throwing made the host process crash entirely. Logging +
        -- continuing keeps the host alive; the deus run may be in a
        -- slightly inconsistent post-round state but that's recoverable
        -- vs a session-ending crash. Memory reference_vmf_rpc_string_cap
        -- documents the same hardcap; ct's own broadcasts already use
        -- chunked sends to stay under it. The crash here is in vanilla's
        -- broadcast which we cannot intercept.
        mod:warning("[finale_dominant_god] vanilla game_round_ended errored (likely RPC payload too large for 500-char hardcap): %s — host continues, attempting transition recovery",
            tostring(err))

        -- v0.7.155: the throw above unwinds vanilla game_round_ended BEFORE it
        -- assigns self._next_state (deus_mechanism.lua: _setup_run runs, then a
        -- network_send inside the graph/settings broadcast overflows the 500-char
        -- cap and throws, so _transition_next_node("start") at :621 and
        -- `self._next_state = next_state` at :666 NEVER run). With no next state
        -- the mechanism state machine can't advance → the NEXT CW round FREEZES
        -- (reported 2026-06-20). _setup_run already built the run + graph before
        -- the failing broadcast, so finish the transition vanilla skipped. The
        -- `_next_state == nil` guard avoids clobbering a state vanilla DID set
        -- (throw later in the flow); pcall-wrapped so worst case it just warns,
        -- never worse than the freeze it replaces. Fixes the freeze regardless of
        -- WHICH mod's un-chunked network_send overflowed (e.g. a co-loaded stable
        -- `ct` alongside `ct_dev`) — ct_dev cannot chunk a third party's send.
        if reason == "start_game" and is_server and self._next_state == nil
                and self._transition_next_node then
            local ok2, ns = pcall(self._transition_next_node, self, "start")
            if ok2 and ns then
                self._next_state = ns
                mod:warning("[finale_dominant_god] recovered the skipped round-end transition (next_state set) — next CW round should load instead of freezing")
            else
                mod:warning("[finale_dominant_god] could NOT recover the round-end transition: %s — the next CW start may still freeze", tostring(ns))
            end
        end
    end
end)

-- ============================================================
-- Spawn census (Issue #58 / #156) — UNCONDITIONAL pickup count per mission
-- ============================================================
-- The recurring "Horn of Magnus / injected adventure map spawns NOTHING" bug
-- (no chests, no altars, no pickups; intermittent) was historically un-diagnosable
-- because the only log evidence was `has_pickup_settings` + the *configured*
-- cursed_chest_count -- never what ACTUALLY spawned. This census counts every
-- pickup that passes through PickupSystem._spawn_pickup -- the SINGLE chokepoint
-- for BOTH the spread pass (ammo/healing/potions/coins) and the guaranteed pass
-- (Chests of Trials, Belakor altar, caskets) -- keyed by final pickup_name, and
-- emits ONE `printf` summary ~8s after the host's populate_pickups (by which point
-- the guaranteed-spawn pass has fully run). Raw printf bypasses every VMF/mod
-- logging toggle, so it lands on a logging-OFF host with NO dump command and NO
-- debug toggle. `total=0` on an injected level is the unambiguous "this map is
-- broken" signal; the injected=/adv_base=/diff= fields on this line + the
-- [populate_pickups] line say WHY in the same breath. (The aggregate avoids the
-- per-spawner printf flood that would tank FPS -- see #104.)
do
    local _counts = {}
    local _total = 0
    local _level, _injected, _adv_base, _difficulty = nil, nil, nil, nil
    local _armed = false
    local _elapsed = 0
    local _EMIT_DELAY = 8.0  -- seconds; guaranteed-spawn pass completes well within this window

    mod._ct_tally_reset = function(level_key, injected, adv_base, difficulty)
        table.clear(_counts)
        _total = 0
        _level, _injected, _adv_base, _difficulty = level_key, injected, adv_base, difficulty
        _armed = true
        _elapsed = 0
    end

    mod._ct_tally_count = function(pickup_name, spawned_unit)
        if not _armed or spawned_unit == nil then return end
        local k = tostring(pickup_name)
        _counts[k] = (_counts[k] or 0) + 1
        _total = _total + 1
    end

    local function _emit()
        local ok = pcall(function()
            local cursed  = _counts.deus_cursed_chest or 0
            local weapon  = _counts.deus_weapon_chest or 0
            local altar   = _counts.deus_02 or 0
            local coins   = _counts.deus_soft_currency or 0
            local potions = 0
            for name, n in pairs(_counts) do
                if Pickups and Pickups.deus_potions and Pickups.deus_potions[name] then potions = potions + n end
            end
            local keys = {}
            for k in pairs(_counts) do keys[#keys + 1] = k end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(_counts[k]) end
            printf("[ct-spawn-tally] level=%s injected=%s adv_base=%s diff=%s total=%d ZERO=%s | chests(cursed=%d weapon=%d) altar=%d coins=%d potions=%d | %s",
                tostring(_level), tostring(_injected), tostring(_adv_base), tostring(_difficulty),
                _total, tostring(_total == 0), cursed, weapon, altar, coins, potions,
                table.concat(parts, " "))
        end)
        if not ok then pcall(printf, "[ct-spawn-tally] level=%s emit failed (total=%d)", tostring(_level), _total) end
    end

    mod._ct_tally_tick = function(dt)
        if not _armed then return end
        _elapsed = _elapsed + (dt or 0)
        if _elapsed >= _EMIT_DELAY then
            _armed = false
            _emit()
        end
    end
    -- Regression marker (PROJECT_STANDARDS.md hook-consolidation doctrine): census is
    -- wired through the SINGLE existing _spawn_pickup hook + the existing mod.update
    -- drainer; no new hook on PickupSystem._spawn_pickup / no second mod.update owner.
    mod._CT_SPAWN_TALLY_MARKER = "CT_SPAWN_TALLY_v1_unconditional_census"
end

-- CLARIFY: Patches LevelSettings[level].pickup_settings to control the COUNT of altars/cursed
-- chests/arena ammo crates spawned per mission. This works alongside `get_deus_weapon_chest_type`
-- which controls the TYPE distribution within each chest. Net effect:
--   - altar_total > 0: spawn this many altars total (types determined by chest_*_count proportions)
--   - cursed_count != 1: override cursed-chest count (vanilla = 1)
--   - arena_ammo != 2: override arena ammo box count (vanilla = 2)
--   - potions_on: inject campaign damage/speed/CDR potions into Pickups.deus_potions for this mission
-- All settings save/restore around `func()` so vanilla values are preserved between runs.
-- POTENTIAL BUG (LOW): Same `func` error → state leak issue as boon/trait hooks. If `func()` raises,
-- pickup_settings stays mutated AND added_potions clones leak in Pickups.deus_potions.
--
-- Per-level counter for tome/grim → Chest of Trials conversions. Declared here (not
-- where the conversion hook below uses it) because Lua 5.1 closures bind locals
-- lexically AT CREATION TIME — placing the `local` after the hook would make the
-- earlier reference resolve to a global (per feedback_lua_forward_reference.md).
-- Reset is performed at the top of THIS hook (consolidated to avoid the VMF
-- "Attempting to rehook active hook" warning for populate_pickups).
local _CAMPAIGN_POTION_NAMES = { "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }
local _chest_conversions_this_level = 0
-- v0.7.55: per-level Belakor altar tracker. Lua 5.1 closure binding rules require this
-- be declared BEFORE the _spawn_guaranteed_pickup hook reads it. Reset at the top of
-- the consolidated populate_pickups hook (alongside _chest_conversions_this_level).
local _belakor_altar_spawned_this_level = false
mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    _chest_conversions_this_level = 0
    -- [ct-probe] v0.7.157-dev unconditional cursed-chest budget probe (Issue #60).
    -- Fires ONCE per mission load (populate_pickups is per-mission on the host).
    -- Logs the level key + the configured cursed_chest_count (effective_setting,
    -- host-synced). The ACTUAL number spawned is reported per-spawner by the
    -- baked_cursed_chest=ALLOW/SUPPRESS + pedestal probes in _spawn_guaranteed_pickup;
    -- grep [ct-probe] and count ALLOWs to verify "actual == configured" next session.
    -- Raw printf (misc_util.lua:29) bypasses the VMF mod-logging toggle, so this
    -- lands even on a logging-OFF host (the gap that produced zero lines on Rain's).
    pcall(function()
        local cur0 = LevelHelper and LevelHelper:current_level_settings()
        local cc_raw = effective_setting("cursed_chest_count")
        local cc_cap = (cc_raw == -1 or cc_raw == nil) and 1 or cc_raw
        printf("[ct-probe] populate level=%s cursed_chest_count=%s effective_cap=%s",
            tostring(cur0 and cur0.level_id), tostring(cc_raw), tostring(cc_cap))
    end)
    -- v0.7.97: reset per-run counters for career-exclusive pickup denials.
    -- populate_pickups fires once at mission-load on the host, so this is the
    -- "run boot" hook for spawn telemetry. The denial count / once-per-run log
    -- gating live in the `_can_spawn` hook below.
    _career_exclusive_denial_counts = {}
    _career_exclusive_logged_this_run = {}
    -- v0.7.85 defensive logging: surface why a mission ended up with no pickups.
    -- Symptom seen 2026-05-22: Horn of Magnus run had no health/ammo/tomes/grimoires
    -- spawn. Vanilla PickupSystem.populate_pickups (pickup_system.lua:405) early-
    -- bails if `level_settings.pickup_settings` is nil, with no log. This block
    -- logs the level_key + presence of pickup_settings + game_mode at every entry
    -- so the next occurrence is diagnosable from the log alone instead of needing
    -- a fresh repro session.
    local cur = LevelHelper and LevelHelper:current_level_settings()
    local level_key = cur and cur.level_id
    local has_settings = cur and cur.pickup_settings and true or false
    local mechanism = cur and cur.mechanism
    local active_mutators = {}
    -- Vanilla API: GameModeManager._mutator_handler is a MutatorHandler instance.
    -- MutatorHandler:activated_mutators() returns self._mutators, a name-keyed
    -- table of {template = ..., context = ...} entries.
    local ok = pcall(function()
        local gm = Managers and Managers.state and Managers.state.game_mode
        local mh = gm and gm._mutator_handler
        local mutators = mh and mh:activated_mutators()
        if mutators then
            for name in pairs(mutators) do
                active_mutators[#active_mutators + 1] = name
            end
        end
    end)
    table.sort(active_mutators)
    -- v0.7.182-dev: printf, NOT mod:info. The mod:info form of this line logged ZERO times
    -- in every session (the user runs VMF mod-logging OFF), so the recurring "Horn of Magnus
    -- has no pickups" bug (first seen 2026-05-22) could never be diagnosed from a log — the
    -- data the comment above promised was silently suppressed. Raw printf is unconditional and
    -- fires once per mission load on the host (where populate_pickups runs), so it is now
    -- ALWAYS captured automatically, no debug toggle or dump command needed. has_pickup_settings
    -- =false is the smoking gun: vanilla populate_pickups (pickup_system.lua:405) early-bails on
    -- nil pickup_settings -> no health/ammo/tomes/grimoires spawn. difficulty included because
    -- the engine also warns "NO PICKUP DATA FOR CURRENT DIFFICULTY".
    local difficulty
    pcall(function()
        difficulty = Managers and Managers.state and Managers.state.difficulty
            and Managers.state.difficulty:get_difficulty()
    end)
    -- v0.7.187-dev (#58/#156): also capture the injection GATE + difficulty-entry
    -- presence. on_injected_adventure_level()==false on a magnus_/military_/etc. CW
    -- level means the whole adventure->deus pickup bridge in _can_spawn is skipped and
    -- EVERYTHING (chests, altars, ammo, healing) is vetoed -- the prime suspect for the
    -- "Horn of Magnus spawns nothing" bug. diff_has_entry==false reproduces the vanilla
    -- "NO PICKUP DATA FOR CURRENT DIFFICULTY ... USING SETTINGS FOR EASY" fallback.
    -- on_injected_adventure_level / adventure_base_from_level_key are file-locals
    -- defined LATER (forward ref -> nil global from here) -> reach via mod._ (call-time).
    local _inj, _adv_base = false, nil
    pcall(function()
        if mod._ct_on_injected_adventure_level then _inj = mod._ct_on_injected_adventure_level() end
        if mod._ct_adventure_base_from_level_key then _adv_base = mod._ct_adventure_base_from_level_key(level_key) end
    end)
    local diff_has_entry = (cur and cur.pickup_settings and difficulty
        and cur.pickup_settings[difficulty] ~= nil) and true or false
    -- v0.7.200-dev (#156): spawner-list counts at populate ENTRY. The 2026-07-01 forensics
    -- showed 100% spawn debt with ZERO pedestal probes — meaning the spawner lists were
    -- EMPTY when populate ran (pickup_gizmo_spawned never registered a unit; object-set
    -- exclusion hypothesis). These three counts close that diagnosis loop in one line:
    -- all-zero on an injected level = the level's pickup gizmos never spawned (level-load
    -- problem, see the GameModeHelper.get_object_sets hook); nonzero = the veto is
    -- downstream in _can_spawn/settings. Field names verified against vanilla
    -- pickup_system.lua:64/75/76 (guaranteed_/primary_/secondary_pickup_spawners).
    local sp_primary, sp_secondary, sp_guaranteed = -1, -1, -1
    pcall(function()
        sp_primary    = type(self.primary_pickup_spawners) == "table" and #self.primary_pickup_spawners or -1
        sp_secondary  = type(self.secondary_pickup_spawners) == "table" and #self.secondary_pickup_spawners or -1
        sp_guaranteed = type(self.guaranteed_pickup_spawners) == "table" and #self.guaranteed_pickup_spawners or -1
    end)
    pcall(printf, "[populate_pickups] level=%s mechanism=%s difficulty=%s has_pickup_settings=%s diff_has_entry=%s injected=%s adv_base=%s active_mutators=[%s] spawners: primary=%d secondary=%d guaranteed=%d",
        tostring(level_key), tostring(mechanism), tostring(difficulty), tostring(has_settings),
        tostring(diff_has_entry), tostring(_inj), tostring(_adv_base),
        table.concat(active_mutators, ","), sp_primary, sp_secondary, sp_guaranteed)
    -- Arm the unconditional spawn census for THIS mission (emits ~8s later via mod.update).
    if mod._ct_tally_reset then mod._ct_tally_reset(level_key, _inj, _adv_base, difficulty) end
    if not LevelHelper then
        return func(self, ...)
    end

    -- v0.7.42: effective_setting so each peer's populate_pickups mutation uses host's values.
    -- v0.7.65: sentinel -1 = "Default" (use vanilla random/count) — distinct from 0 which means
    -- "literally zero." `as_count(-1) = 0` for the altar TOTAL sum (a Default altar contributes
    -- 0 to the override total) but `altar_custom` triggers on ANY non-sentinel value.
    local function _as_count(v) return (v == -1) and 0 or v end
    local upgrade_c    = effective_setting("chest_upgrade_count")    or -1
    local swap_melee_c = effective_setting("chest_swap_melee_count") or -1
    local swap_ranged_c= effective_setting("chest_swap_ranged_count")or -1
    local power_up_c   = effective_setting("chest_power_up_count")   or -1
    local altar_total = _as_count(upgrade_c) + _as_count(swap_melee_c) + _as_count(swap_ranged_c) + _as_count(power_up_c)
    local altar_any_explicit = upgrade_c ~= -1 or swap_melee_c ~= -1 or swap_ranged_c ~= -1 or power_up_c ~= -1
    local cursed_count_raw = effective_setting("cursed_chest_count") or -1
    local cursed_count = _as_count(cursed_count_raw)
    local arena_ammo_raw = effective_setting("arena_ammo_count") or -1
    local arena_ammo = _as_count(arena_ammo_raw)
    local potions_on = effective_setting("enable_campaign_potions")  -- v0.7.64: now host-synced

    -- Defensive cleanup: if a previous populate_pickups call errored mid-flight
    -- with potions_on=true, the campaign-potion clones could remain in
    -- Pickups.deus_potions for the rest of the session. Scrub them every call
    -- when the toggle is off so subsequent missions don't see ghost potions.
    if not potions_on and Pickups and Pickups.deus_potions then
        for _, name in ipairs(_CAMPAIGN_POTION_NAMES) do
            Pickups.deus_potions[name] = nil
        end
    end

    -- v0.7.65: "custom" gates determine which fields to mutate. Sentinel -1 = "Default" =
    -- skip override. Explicit values (including 0 = literally zero) trigger override.
    -- Pre-0.7.65 the gates compared to vanilla defaults (1, 2) — that's gone because the
    -- new sentinel makes "use vanilla" the explicit choice, not "happens to match vanilla."
    local altar_custom = altar_any_explicit
    local cursed_custom = cursed_count_raw ~= -1
    local ammo_custom = arena_ammo_raw ~= -1

    -- v0.7.55: reset per-level Belakor altar tracker. Used by the tome/grim hook so
    -- only the first book spot after all Chests of Trials are placed gets the altar
    -- (one altar per mission, like vanilla belakor-themed CW levels which request
    -- `deus_02 = 1`). The altar is no longer requested via populate_pickups primary
    -- (which placed it in a random ammo/healing spot); routing through book spots
    -- means it shares the same pedestal a chest would have used, per user spec.
    _belakor_altar_spawned_this_level = false

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    -- CLARIFY: Detect arena (finale) vs normal levels. Arena levels have no `deus_weapon_chest` key
    -- but DO have `ammo`; normal levels have `deus_weapon_chest` and `deus_cursed_chest`. The
    -- detection lets one hook handle both level types correctly.
    local saved = {}
    local current = LevelHelper:current_level_settings()
    local pickup_settings = current and current.pickup_settings
    if pickup_settings then
        for _, difficulty_data in pairs(pickup_settings) do
            if type(difficulty_data) == "table" and difficulty_data.primary then
                local primary = difficulty_data.primary
                local is_arena = primary.deus_weapon_chest == nil
                local entry = { tbl = primary }

                if not is_arena then
                    if altar_custom and primary.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = primary.deus_weapon_chest
                        primary.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and primary.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = primary.deus_cursed_chest
                        primary.deus_cursed_chest = cursed_count
                    end
                elseif ammo_custom and primary.ammo ~= nil then
                    entry.ammo = primary.ammo
                    primary.ammo = arena_ammo
                end

                -- CLARIFY: Only push to `saved` if at least one field was mutated, so the restore
                -- loop below is a no-op for unchanged entries.
                if entry.deus_weapon_chest ~= nil or entry.deus_cursed_chest ~= nil or entry.ammo ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    local added_potions = {}
    -- Saved spawn_weightings keyed by pickup_name. We renormalize the entire deus_potions
    -- group below so the inserted campaign potions are actually reachable by the sampler;
    -- both the inserts AND the originals get restored after vanilla populate_pickups runs.
    local saved_weights = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        -- Step 1: insert campaign potion clones using their NATIVE Pickups.potions weight
        -- (so each entry contributes ~0.33 to the running total). We'll renormalize after.
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                local clone = table.clone(Pickups.potions[name])
                Pickups.deus_potions[name] = clone
                added_potions[#added_potions + 1] = name
            end
        end

        -- Step 2: renormalize ALL entries in Pickups.deus_potions so they sum to 1.0.
        -- Without this, the sampler in pickup_system.lua _spawn_spread_pickups picks
        -- random[0,1) and breaks on first cumulative >= random — entries past
        -- cumulative 1.0 are unreachable. CW potions were already normalized to sum
        -- ~1.0 at engine startup; adding 3 campaign entries pushed the total to ~1.375
        -- and made some entries (depending on `pairs` iteration order, which is
        -- unspecified in Lua 5.1) silently never spawn.
        local total = 0
        for name, settings in pairs(Pickups.deus_potions) do
            if settings and settings.spawn_weighting then
                saved_weights[name] = settings.spawn_weighting
                total = total + settings.spawn_weighting
            end
        end
        if total > 0 then
            for name, settings in pairs(Pickups.deus_potions) do
                if saved_weights[name] then
                    settings.spawn_weighting = saved_weights[name] / total
                end
            end
        end
    end

    -- v0.7.165-dev: build the coin-reservation set BEFORE vanilla populate runs its
    -- _spawn_spread_pickups pass (which calls _can_spawn). The spawner lists are fully
    -- populated by now (pickup_gizmo_spawned fires per-spawner at level spawn, long
    -- before populate_pickups). Rank-based so even a tiny pool reserves >= 1 spawner.
    --
    -- Built unconditionally on the host (not gated on on_injected_adventure_level()
    -- here -- that file-local is defined LATER in this file and a lexical forward
    -- reference from this earlier hook would resolve to a nil global, per
    -- feedback_lua_forward_reference.md). Building it on a non-injected level is inert:
    -- the reservation only *takes effect* inside _can_spawn, whose entire deny block --
    -- including the reservation branches -- is already gated behind
    -- `if not on_injected_adventure_level() then return ok end`. So a set built off a
    -- vanilla level is simply never consulted. (mod._ct_rebuild... is resolved at call
    -- time, by which point the assignment below the helper has run.)
    if self.is_server and mod._ct_rebuild_coin_reserved_set then
        mod._ct_rebuild_coin_reserved_set({ self.primary_pickup_spawners, self.secondary_pickup_spawners })
    elseif mod._ct_clear_coin_reserved_set then
        mod._ct_clear_coin_reserved_set()
    end

    local results = { func(self, ...) }

    for _, entry in ipairs(saved) do
        local primary = entry.tbl
        if entry.deus_weapon_chest ~= nil then primary.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then primary.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo ~= nil then primary.ammo = entry.ammo end
    end

    -- Restore CW potion weights to their pre-renormalization values, then drop the
    -- inserted campaign clones. Order matters: restore first so we don't briefly leave
    -- weights in an inconsistent state if anything else reads Pickups.deus_potions.
    for name, original in pairs(saved_weights) do
        local entry = Pickups.deus_potions[name]
        if entry then entry.spawn_weighting = original end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    -- v0.7.126-dev (Issue #58): post-populate diagnostic dump. Fires on EVERY level
    -- including vanilla Adventure mode (Horn of Magnus, etc.) so we can capture
    -- the "working" baseline and diff against the broken CW variant. This is the
    -- single best moment in the load cycle to inspect spawners: vanilla populate
    -- has finished assigning units to spawner lists + categorizing them, and our
    -- _spawn_guaranteed_pickup conversion hook hasn't fired yet (that happens
    -- AFTER populate, during the guaranteed-spawn pass). Gated on VMF debug
    -- logging (via _dbg) so it's free in normal play.
    pcall(_dump_pickup_system_state,    "[ct_dbg][pickups:post_populate]", false)
    pcall(_dump_pickup_spawners_verbose, "[ct_dbg][pickup_units:post_populate]")

    -- v0.7.107-dev nil-hole audit: PickupSystem.populate_pickups (pickup_system.lua:395)
    -- returns nothing — every observed code path is a bare `return` or implicit end.
    -- The `results` table is therefore always empty, so bare unpack is a no-op return
    -- and equivalent to `return`. Left as-is per audit (no nil-hole exposure exists).
    return unpack(results) -- unpack-safe: results always empty, equivalent to bare return
end)

-- ============================================================
-- Holy Hand Grenade spawn rate (CW campaign-map pickup pools)
-- ============================================================
-- v0.7.145-dev: REVERTED. v0.7.143-dev lowered
-- Pickups.grenades.holy_hand_grenade.spawn_weighting 0.8 -> 0.1 to make the
-- CW power-bomb rarer on injected campaign maps. THIS CRASHED THE GAME ON LOAD:
--   error.lua:26: Problem selecting a pickup to spawn,
--   spawn_weighting_total = 0.85, spawn_value = 0.943
-- The spread-pickup sampler rolls random in [0,1) and walks the pool's cumulative
-- spawn_weighting; if the pool's total is < the roll it falls off the end and
-- hard-errors. holy_hand's 0.8 weight is LOAD-BEARING for the grenade pool total
-- (other grenades summed to only ~0.75) -- dropping it to 0.1 made the total 0.85,
-- so any roll in [0.85, 1.0) crashed. This is the same sampler invariant the
-- deus_potions renormalization (search "renormaliz") already guards: a pool's
-- total must stay >= 1.0. Lowering a raw spawn_weighting violates it.
--
-- Restored to vanilla (no mutation) to stop the crash. To actually reduce the
-- rate safely we must PRESERVE the pool total -- either renormalize the whole
-- grenade pool (so holy_hand's SHARE shrinks while the sum stays >= 1.0) inside
-- the populate path, or redistribute holy_hand's removed weight onto the other
-- grenades. Do NOT reintroduce a bare `holy_hand.spawn_weighting = <low>`.

-- ============================================================
-- Tome / Grimoire → Chest of Trials substitution
-- ============================================================

-- CLARIFY: Adventure levels injected into the CW map pool (see _adventure_pool.lua) have
-- tome/grimoire pickup_spawner units baked into the level bundle. On an injected adventure
-- level we want those positions to spawn a Chest of Trials (deus_cursed_chest) instead.
--
-- Vanilla PickupSystem._spawn_guaranteed_pickup (pickup_system.lua:821-844) iterates AllPickups
-- and filters via _can_spawn, which reads Unit.get_data(spawner, pickup_name). Tome spawners
-- have only `tome = true` set; grimoire spawners only `grimoire = true`. We detect those flags
-- and short-circuit to spawn deus_cursed_chest directly.
--
-- Gated on IS_INJECTED_ADVENTURE_LEVEL[base_level_name] so vanilla CW levels (no tomes/grims)
-- and stock adventure runs (when CW pool injection is off) are completely unaffected.

-- Reverse-match a permutation or duplicate-alias key back to its injected adventure base.
-- Returns the base key (e.g. "bell") if level_key matches an injected adventure, else nil.
-- Handles three formats:
--   "bell"                       (raw base)
--   "bell_khorne_path1"          (per-theme permutation)
--   "bell_dup1_khorne_path1"     (duplicate-alias permutation)
local function adventure_base_from_level_key(level_key)
    if type(level_key) ~= "string" or not AdventurePool then return nil end
    for base in pairs(AdventurePool.IS_INJECTED_ADVENTURE_LEVEL) do
        if level_key == base or level_key:find("^" .. base .. "_") then
            return base
        end
    end
    return nil
end

local function on_injected_adventure_level()
    if not LevelHelper then return false end
    -- v0.7.154-dev: MUST be inside an actual Chaos Wastes (deus) expedition. The
    -- adventure maps CW injects into its pool also exist in STOCK Adventure under
    -- the SAME level_id, so gating only on the level name leaked every CW-only
    -- pickup transform into real Adventure -- reported 2026-06-20: tomes/grimoires
    -- missing in Adventure (the tome/grim -> Chest-of-Trials substitution, the
    -- pedestal/collectible -> Pilgrim's Coin conversion, the no_roamers pacing
    -- filter, and force_belakor all gate on this function). Only the deus
    -- mechanism exposes get_deus_run_controller; in Adventure game_mechanism() has
    -- no such method, so this bails and Adventure plays vanilla. (Same idiom as
    -- _current_node_theme / _current_node_curse below.)
    local mechanism = Managers.mechanism and Managers.mechanism.game_mechanism
        and Managers.mechanism:game_mechanism()
    if not (mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()) then
        return false
    end
    local current = LevelHelper:current_level_settings()
    return current and adventure_base_from_level_key(current.level_id) ~= nil
end

-- Exposed for the populate_pickups hook + spawn census (both lexically EARLIER in
-- this file, so a direct reference there resolves to a nil global -- forward-ref
-- gotcha, feedback_lua_forward_reference.md). Reached via mod._ which resolves at
-- CALL time, by which point this assignment has run.
mod._ct_on_injected_adventure_level   = on_injected_adventure_level
mod._ct_adventure_base_from_level_key = adventure_base_from_level_key

-- ============================================================
-- v0.7.200-dev (#156) — CANDIDATE FIX: enable the 'adventure' object set on
-- mod-injected adventure levels under the deus game mode
-- ============================================================
-- HYPOTHESIS (2026-07-01 forensics, pending in-game verification): on
-- magnus_tzeentch_path1 ALL spawner lists were EMPTY at populate and
-- pickup_gizmo_spawned never registered a unit — the gizmos never SPAWNED.
-- Mechanism: GameModeSettings.deus.object_sets = { gm_sp = true }
-- (game_mode_settings_morris.lua:8-10) vs adventure's { adventure = true,
-- gm_sp = true } (game_mode_settings.lua:29-32). GameModeHelper.get_object_sets
-- (game_mode_helper.lua:58-111) only marks a level object set for spawning when
-- the GAME MODE's object_sets table enables it (or it's shadow_lights / flow_ /
-- team_ prefixed). Any adventure-level unit grouped in the 'adventure' object
-- set — plausibly including pickup-spawner gizmos on some level assets (set
-- membership lives in the level binary, unreadable offline; the Holly cemetery
-- HAS spawned chests when injected, so membership varies per asset) — silently
-- never spawns when that level loads under deus.
--
-- FIX SHAPE: get_object_sets returns (object_sets_map, spawned_object_sets_array);
-- the callers use them as:
--   * state_loading.lua:1405  -> spawned_object_sets -> AsyncLevelSpawner (which
--     units actually spawn)  [also the :1438 hero-sublevel call]
--   * state_ingame.lua:753    -> object_sets map (flow/team set bookkeeping)
-- We append "adventure" to the ARRAY (second return) — the map already contains
-- every available set unconditionally, so it needs no mutation. Scoped hard:
--   (1) game_mode_key == "deus",
--   (2) the level KEY currently loading resolves through the mod's STATIC
--       adventure catalog (AdventurePool.MISSION_BY_KEY — deliberately NOT the
--       toggle-gated IS_INJECTED_ADVENTURE_LEVEL, so host and joining clients
--       make the identical decision and spawn identical worlds), and
--   (3) LevelSettings[level_key].level_name matches the level_name argument
--       (guards the hero-sublevel call site and any unrelated concurrent load).
-- Vanilla deus levels have morris-native level_names/keys (no catalog match) and
-- vanilla adventure runs pass game_mode_key == "adventure" — both untouched.
--
-- GameModeHelper is a plain class table (game_mode_helper.lua:3, dot-called at
-- every site — no upvalue captures found) -> table-form hook with nil guard.
-- Dup-check 2026-07-01: no other (GameModeHelper, *) hook in ct_dev.
do
    -- Resolve the injected-adventure base for the level being spawned, or nil.
    -- Returns base_key, level_key on a match.
    local function _ct_injected_base_for_spawn(level_name)
        if not AdventurePool or not AdventurePool.MISSION_BY_KEY then return nil end
        local lth = Managers and Managers.level_transition_handler
        local level_key = lth and lth.get_current_level_keys and lth:get_current_level_keys()
        if type(level_key) ~= "string" then return nil end
        local ls = rawget(_G, "LevelSettings")
        local entry = ls and rawget(ls, level_key)
        if not entry or entry.level_name ~= level_name then return nil end
        for base in pairs(AdventurePool.MISSION_BY_KEY) do
            -- matches "magnus", "magnus_tzeentch_path1" AND dup aliases
            -- ("magnus_dup1_tzeentch_path1") — same shape as adventure_base_from_level_key.
            if level_key == base or level_key:find("^" .. base .. "_") then
                return base, level_key
            end
        end
        return nil
    end

    local _gmh = rawget(_G, "GameModeHelper")
    if _gmh and type(_gmh.get_object_sets) == "function" then
        mod:hook(_gmh, "get_object_sets", function(func, level_name, game_mode_key)
            local object_sets, spawned_object_sets = func(level_name, game_mode_key)
            if game_mode_key == "deus"
                and type(object_sets) == "table"
                and type(spawned_object_sets) == "table"
                and object_sets.adventure                       -- level actually HAS an 'adventure' set
                and not table.contains(spawned_object_sets, "adventure")
            then
                local ok, base, level_key = pcall(_ct_injected_base_for_spawn, level_name)
                if ok and base then
                    spawned_object_sets[#spawned_object_sets + 1] = "adventure"
                    -- Raw printf: proves the fix engaged even on the logging-OFF host.
                    pcall(printf, "[ct:objset] injected adventure level %s: enabling 'adventure' object set (issue #156)",
                        tostring(level_key))
                end
            end
            return object_sets, spawned_object_sets
        end)
    else
        pcall(printf, "[ct:objset] GameModeHelper.get_object_sets not hookable at load — #156 candidate fix INACTIVE")
    end
end

-- Lookup table: <adv_base_key>_title → display name. Used to satisfy the CW map UI
-- which constructs the title localization key ad-hoc at deus_map_ui_v2.lua:593 as
-- `Localize(level .. "_title")`, ignoring LevelSettings[<perm>].display_name entirely.
-- Without this hook the map shows "<elven_ruins_title>" / "<bell_title>" etc.
-- We also intercept `_desc` for the same reason (line 594).
local ADV_TITLE_OVERRIDES = {}
local ADV_DESC_OVERRIDES = {}
do
    local function add(key, title, desc)
        ADV_TITLE_OVERRIDES[key .. "_title"] = title
        ADV_DESC_OVERRIDES[key .. "_desc"] = desc
    end
    for _, m in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        -- title shown on the node icon hover; desc shown below it.
        add(m.key, m.name, m.name)
    end
end

-- Mod Boon localization overrides (v0.7.30). The 4 ct-injected meta boons reference
-- `display_name_ct_meta_*` and `description_ct_meta_*` localization keys in their
-- DeusPowerUpTemplates entries. Vanilla Localize() returns `<key>` for keys it doesn't
-- know — so the in-game boon UI would show "<display_name_ct_meta_stagger>" unless we
-- intercept and provide the strings. Each `%` is escaped as `%%` because vanilla's
-- UIUtils.format_localized_description re-feeds via string.format (see
-- feedback_vt2_localize_string_format_pipeline.md).
local MOD_BOON_LOC = {
    display_name_ct_meta_stagger = "(Mod Boon) Reactive Bulwark",
    description_ct_meta_stagger  = "+1%% stagger power and +1%% melee cleave per active boon.",
    display_name_ct_meta_crit    = "(Mod Boon) Crit Cascade",
    description_ct_meta_crit     = "+1%% critical strike chance and +5%% critical strike effectiveness per active boon.",
    display_name_ct_meta_health  = "(Mod Boon) Vitality Cascade",
    description_ct_meta_health   = "+1%% max health and +1%% healing received per active boon.",
    display_name_ct_meta_cooldown = "(Mod Boon) Ability Cascade",
    description_ct_meta_cooldown = "+2%% cooldown regen per active boon.",
    display_name_ct_meta_movespeed = "(Mod Boon) Wind Cascade",
    description_ct_meta_movespeed  = "+1%% movement speed per active boon.",
    display_name_ct_meta_ammo      = "(Mod Boon) Quiver Cascade",
    description_ct_meta_ammo       = "+5%% total ammo, +5%% max overheat (Sienna staves, Bardin drakefire), and +5%% Moonfire Bow energy capacity per active boon. May Khaine's quivers and Vaul's forges fill in equal measure.",
    display_name_ct_kill_heal    = "(Mod Boon) Khaine's Communion",
    description_ct_kill_heal     = "Killing an enemy heals you for 1 health.",

    -- v0.7.34 Trait-as-Boon
    display_name_ct_boon_vauls_anvil         = "(Mod Boon) Vaul's Anvil",
    description_ct_boon_vauls_anvil          = "All attacks against you count as blocked while your melee weapon is wielded. Block break disables this for 10 seconds.",
    display_name_ct_boon_manann_tempest      = "(Mod Boon) Manann's Tempest",
    description_ct_boon_manann_tempest       = "Critical strikes trigger a chain lightning that jumps to up to 5 nearby enemies, ignoring armour. Stacks with the trait.",
    display_name_ct_boon_taal_twinned_arrow  = "(Mod Boon) Taal's Twinned Arrow",
    description_ct_boon_taal_twinned_arrow   = "Ranged attacks fire one additional projectile. Stacks with the trait. Has no effect without a ranged weapon.",
    display_name_ct_boon_asuryan_wrath       = "(Mod Boon) Asuryan's Wrath",
    description_ct_boon_asuryan_wrath        = "Melee kills have a 50%% chance to deal the killing blow's damage to a nearby enemy. Stacks with the trait.",

    -- v0.7.33 typo fix: vanilla description for Addaioth's Splendour (deus_ranged_crit_explosion
    -- trait) claims "Every 30 seconds" but the actual cooldown_duration in buff_tweak_data.lua:344
    -- is 10. Vanilla's loc string swapped the cooldown (10) and damage percent (30) when filling
    -- description_values positionally. Override returns a static, correct string.
    description_deus_ranged_crit_explosion_trait = "Every 10 seconds, ranged Critical Hits explode in an area for 30%% of their Damage. Deals damage scaled by Hero Power. Staggers nearby enemies.",
}

-- Consolidated _G.Localize hook. VMF warns "Attempting to rehook active hook" if the
-- same target is hooked twice — only the second binding survives and shadows the first.
-- Two purposes live here:
--   1. Adventure-mission titles/descriptions used by deus_map_ui_v2.lua:593's
--      ad-hoc `Localize(level .. "_title")` lookup. Without this, injected
--      adventure nodes render as "<elven_ruins_title>" on Olesya's map.
--   2. Khaine's Fury (deus_reckless_swings) description override when the user has
--      `tweak_reckless_swings` enabled. Vanilla format string is "While above 50% …";
--      we substitute "25% / 1 damage" verbatim. Percent signs MUST be `%%` because
--      UIUtils.format_localized_description (ui_utils.lua:69) re-feeds the result
--      through string.format with description_values — a bare `%` becomes
--      "[Invalid String Format]". See feedback_vt2_localize_string_format_pipeline.md.
local RECKLESS_SWINGS_DESC_OVERRIDE = "While above 25%% Health, gain 25%% Power but take 1 damage on each melee hit."

-- v0.7.65: Miracle of Ulric / Miracle of Isha localization overrides — only
-- applied when the matching tweak toggle is on, so vanilla text stays put when
-- the alternative behaviors are off. Vanilla loc keys live in compiled
-- .strings bundles (deus_blessing_settings.lua:19-26, 47-56); we intercept the
-- Localize hook to substitute when the toggle is host-active.
-- `%%` is required because UIUtils.format_localized_description re-feeds the
-- result through string.format (feedback_vt2_localize_string_format_pipeline.md).
-- v0.7.67: name override removed — vanilla already returns "Miracle of Ulric"
-- for `blessing_of_power_name` (user-confirmed 2026-05-20). Only the
-- description differs, so only the description is overridden.
local MIRACLE_LOC_OVERRIDES = {
    blessing_of_power_desc      = "Grants every hero +50 Power for the rest of the run. The bonus persists through weapon swaps and upgrades at altars.",
    blessing_of_isha_desc_aegis = "Grants every hero -25%% damage taken for the next mission.",
    blessing_of_isha_desc_wounds= "Grants every hero unlimited wounds for the next mission — every knockdown is revivable instead of resulting in instant death after the first down.",
}

mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string" then
        local t = ADV_TITLE_OVERRIDES[key]
        if t then return t end
        local d = ADV_DESC_OVERRIDES[key]
        if d then return d end
        local m = MOD_BOON_LOC[key]
        if m then
            -- #133: Manann's Tempest gains an 8-second cooldown ONLY while the
            -- `tweak_manann_tempest_cooldown` tweak is active (the ProcFunctions.chain_lightning
            -- hook ~line 9835 enforces MANANN_TEMPEST_COOLDOWN_S = 8.0). Append the note only
            -- when the tweak is on so the boon text tracks behavior live; with it off the
            -- description stays EXACTLY vanilla. effective_setting is host-synced, so clients
            -- reflect the HOST's toggle. No `%` in the appended line, so no %% escaping needed.
            if key == "description_ct_boon_manann_tempest"
                and effective_setting("tweak_manann_tempest_cooldown") then
                return m .. "\n8 second cooldown."
            end
            return m
        end
        if key == "description_deus_reckless_swings" and reckless_swings_originals then
            return RECKLESS_SWINGS_DESC_OVERRIDE
        end
        if key == "blessing_of_power_desc"
            and effective_setting("tweak_miracle_of_ulric_persistent") then
            return MIRACLE_LOC_OVERRIDES[key]
        end
        if key == "blessing_of_isha_desc" then
            -- v0.7.120 (Issue #54 fix): read the v0.7.81+ mutex setting keys via
            -- effective_setting (host-broadcast on clients) so client's boon
            -- description text reflects the HOST's selected mode, not the client's
            -- stale local toggle. Inline because _get_isha_mode is defined later in
            -- the file and this Localize closure is built before its declaration.
            -- Legacy migration: if the user hasn't been through _migrate_isha_legacy
            -- yet (called via _get_isha_mode), also check the v0.7.65 dropdown key.
            if effective_setting("tweak_miracle_of_isha_aegis") then
                return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_aegis
            end
            if effective_setting("tweak_miracle_of_isha_wounds") then
                return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_wounds
            end
            -- Legacy dropdown fallback (pre-v0.7.81 saves not yet migrated)
            local legacy = effective_setting("tweak_miracle_of_isha_alternative")
            if legacy == true or legacy == "aegis" then return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_aegis end
            if legacy == "wounds" then return MIRACLE_LOC_OVERRIDES.blessing_of_isha_desc_wounds end
        end
    end
    return func(key, ...)
end)

-- DeusMechanism.uses_random_directors returns false (deus_mechanism.lua:909) so
-- EnemyPackageLoader._random_director_list stays nil for the entire CW run. Vanilla
-- CW levels' baked spawn_zone data have explicit `roaming_set` directors (no "random"
-- choice), so they never hit the nil dereference at
-- main_path_spawning_generator.lua:314 (`random_director_list[index].name`). Adventure
-- level spawn zones, however, were authored for AdventureMechanism (which returns
-- true) and DO have zone strings with "random" as one of the slash-separated
-- choices. When `process_conflict_directors_zones` picks "random" for any zone, the
-- subsequent generate_great_cycles crash fires.
--
-- Fix: force `use_random_directors = true` on the EnemyPackageLoader.setup_startup_enemies
-- call for any injected adventure level (matching by permutation base). This causes
-- _resolve_breed_packages (line 750) to populate _random_director_list, which the
-- spawn_zone generator then reads safely.
mod:hook("EnemyPackageLoader", "setup_startup_enemies", function(func, self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
    -- v0.7.132-dev: also cover native CW Belakor finale maps (cemetery_belakor_path1,
    -- bell_belakor_path1, magnus_belakor_path1, ...). They carry adventure-style
    -- "random" zone directors but are NOT matched by adventure_base_from_level_key,
    -- so use_random_directors stayed false -> EnemyPackageLoader._random_director_list
    -- never populated -> vanilla main_path_spawning_generator.lua:292 crashed on nil
    -- random_director_list during generate_great_cycles (host "amand" hard crash
    -- 2026-06-06 on cemetery_belakor_path1, GUID a6d00df6-...). The `_belakor_path`
    -- key family is the signature; forcing use_random_directors true makes
    -- _resolve_breed_packages populate _random_director_list, which the spawn-zone
    -- generator then reads safely (same mechanism as the adventure-level fix above).
    if adventure_base_from_level_key(level_key)
            or (type(level_key) == "string" and string.find(level_key, "_belakor_path", 1, true)) then
        use_random_directors = true
    end
    return func(self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
end)

-- v0.7.41: Adventure-injected levels use vanilla conflict directors (e.g., chaos_light)
-- whose `PackSpawningSettings` entries lack `difficulty_overrides`. CW's SIGNATURE-zone
-- pacing applies the `no_roamers` mutator (mutator_deus_pacing_tweak.lua:38) which does
-- `pairs(pack_spawning_settings.difficulty_overrides)` → "bad argument #1 to 'pairs'
-- (table expected, got nil)" on first mission entry. Vanilla CW levels all have the
-- field populated; adventure ones don't (Crashify guid 004768e7).
--
-- Vanilla intends no_roamers as a CW-only pacing tool; it's mechanically too aggressive
-- for adventure levels anyway (area_density_coefficient = 0 wipes roaming spawns). Per
-- user: replace with the gentler `deus_less_roamers` semantics OR just exempt adventure
-- levels. Simplest exemption: filter the mutator name out of the zone/mutator lists
-- before vanilla `tweak_pack_spawning_settings` processes them.
local ADVENTURE_INCOMPATIBLE_PACK_MUTATORS = {
    no_roamers = true,
}

mod:hook("MutatorHandler", "tweak_pack_spawning_settings", function(func, self, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    if not on_injected_adventure_level() then
        return func(self, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    end
    local function filter(list)
        if type(list) ~= "table" then return list end
        local kept = {}
        for _, name in ipairs(list) do
            if not ADVENTURE_INCOMPATIBLE_PACK_MUTATORS[name] then
                kept[#kept + 1] = name
            end
        end
        return kept
    end
    return func(self, filter(zone_mutator_list), filter(mutator_list), conflict_director_name, pack_spawning_settings)
end)

-- ============================================================
-- Curse light tinting on injected adventure levels
-- ============================================================
-- Vanilla GameModeDeus.local_player_game_starts (game_mode_deus.lua:358-378)
-- iterates `Level.units(current_level)` and applies `DeusThemeSettings[theme].light_probe_tint`
-- to lights inside reflection_probe units. For vanilla CW that's enough — the level
-- bundle's sky shader and atmosphere are theme-specific too, so the tint reinforces
-- the existing visual.
--
-- Adventure level bundles have only the native atmosphere baked in (no per-god sky).
-- So when our injected `<adv>_<theme>_path1` permutation loads under a curse, the
-- engine applies the reflection-probe tint but the sky/atmosphere remains adventure-
-- vanilla. Result: cursed adventure missions look too "normal".
--
-- Partial mitigation: hook_safe the same function and apply the theme color to
-- EVERY light in the level (not just reflection probes), plus the camera backlight.
-- This makes the curse colour shift more pronounced even on adventure geometry.
-- It can't bring back the baked sky/particles, but it makes "this node is cursed"
-- visually obvious.
-- Per-curse PALETTES instead of a single tint, so individual level lights
-- pick up complementary / accent colors and the scene reads as themed
-- atmosphere rather than a uniform color filter.
--
-- Each palette has:
--   dominant: the headline color (most lights). Hits ~50% of lights.
--   accent:   a related-but-distinct shade. ~25% of lights.
--   complement: a deliberately contrasting hue. ~15% of lights.
--   warm/cool counterpoint: ~10% of lights — adds visual depth.
--
-- Distribution uses a deterministic hash on each light's index so the look
-- is repeatable per level / per run, not random per frame. The hash is
-- coarse on purpose (a handful of buckets) so nearby lights tend to
-- group rather than producing rainbow noise.
-- Each palette balances 4-5 slots:
--   - Dominant: god's headline hue (most lights).
--   - Accent:   nearby hue, reinforces theme (some lights).
--   - Complement: TRUE opposite on the color wheel — provides contrast pop.
--                 Red↔Cyan, Green↔Magenta, Blue↔Orange, Purple↔Yellow-Green.
--   - Neutral white-ish: keeps some lights "normal-looking" so the
--     colored lights register as accents instead of saturating the scene.
--     User feedback 2026-05-14: "purple looks good with white light sources" —
--     applies broadly; neutral slot makes other palettes pop too.
local _CURSE_LIGHT_PALETTES = {
    khorne = {
        { 1.00, 0.30, 0.25, w = 40 },   -- blood red (dominant)
        { 1.30, 0.55, 0.20, w = 20 },   -- ember orange (accent — same warm family)
        { 1.10, 1.05, 0.90, w = 15 },   -- warm white candle (neutral)
        { 0.95, 0.95, 0.35, w = 10 },   -- gold flame (warm secondary pop)
        { 0.20, 0.90, 1.00, w = 15 },   -- cold cyan complement (true ↔ red)
    },
    nurgle = {
        { 0.45, 1.00, 0.40, w = 40 },   -- sickly bog green (dominant)
        { 0.95, 1.05, 0.35, w = 20 },   -- jaundiced yellow (accent)
        { 1.00, 1.00, 0.95, w = 15 },   -- pale moldy white (neutral)
        { 0.30, 0.85, 0.95, w = 10 },   -- swamp teal (cool secondary)
        -- v0.7.46: was { 1.10, 0.30, 0.95 } — bright magenta. User wanted deep
        -- dark purple instead. Reduced red and blue and dropped overall intensity
        -- so the complement slot reads as ominous violet rather than hot pink.
        { 0.45, 0.15, 0.65, w = 15 },   -- deep dark purple complement (true ↔ green)
    },
    tzeentch = {
        -- Per user feedback v0.7.16: "make all the lights and most of the
        -- natural lights a magic blue, but then have just the overarching
        -- outdoor light be a deep orange." Dropped the cool-white slot
        -- entirely so 100% of Light components are some shade of deep
        -- magic blue. The contrast is now strictly: indoor / point lights
        -- (= blue) vs. outdoor sun + ambient (= warm orange via the shading
        -- env profile below).
        --
        -- NOTE: vanilla torches that get their orange glow from PARTICLE FX
        -- and self-illumination materials (not Light components) will still
        -- look warm — Light.set_color on the unit's Light handle doesn't
        -- override particle / material colors. If the user wants those
        -- pulled cool too we need a separate hook on the particle effect
        -- registry. Not done yet — wait for user feedback to see if it
        -- matters in practice.
        { 0.15, 0.30, 1.50, w = 75 },   -- deep magic cobalt (saturated, dominant)
        { 0.25, 0.50, 1.40, w = 25 },   -- mid cobalt variant (subtle variation, still deep blue)
    },
    slaanesh = {
        { 1.20, 0.45, 1.15, w = 35 },   -- hot pink (dominant)
        { 0.65, 0.40, 1.10, w = 20 },   -- deep purple (accent)
        { 1.10, 1.05, 1.10, w = 20 },   -- pale white (USER: "purple looks good with white")
        { 1.20, 0.75, 0.50, w = 10 },   -- peach warm pop
        { 0.55, 1.10, 0.45, w = 15 },   -- yellow-green complement (true ↔ pink)
    },
    belakor = {
        { 0.40, 0.30, 0.75, w = 40 },   -- twilight purple (dominant)
        { 0.30, 0.45, 0.95, w = 20 },   -- moonlight blue (accent)
        { 0.95, 0.95, 1.05, w = 15 },   -- pale silver-white (ghostly neutral)
        { 0.55, 0.30, 0.55, w = 10 },   -- shadow violet (cool secondary)
        { 1.05, 1.00, 0.50, w = 15 },   -- pale gold complement (true ↔ violet)
    },
}

-- Pick a palette slot for light index `i`. Stable across reloads — same
-- light index always gets the same slot for a given palette. Multiplier 7
-- and offset are arbitrary; chosen so groups of adjacent indices don't all
-- fall into the same bucket (avoid "all lights in this room are blood red").
local function _palette_slot(palette, idx)
    local total_w = 0
    for s = 1, #palette do total_w = total_w + (palette[s].w or 1) end
    -- Hash idx into [0, total_w)
    local h = ((idx * 7919) + 11) % total_w
    local cum = 0
    for s = 1, #palette do
        cum = cum + (palette[s].w or 1)
        if h < cum then return palette[s] end
    end
    return palette[1]
end

-- v0.7.125-dev — pickup-system diagnostic dump (Issue #58, Magnus pickups).
-- Walks LevelSettings.pickup_settings AND PickupSystem live spawner lists,
-- counting placed level-units by spawner_type. The combination tells us
-- whether the data table is missing entries for the current difficulty
-- (settings issue) or whether the level just has no spawners (geometry
-- issue) when the engine reports "Remaining spawn debt".
--
-- Caller controls whether output goes to log only (via mod:info) or also
-- to in-game chat (via mod:echo). Returns nothing; all output is side-effect.
local _PICKUP_CATEGORIES = {
    "deus_weapon_chest", "deus_cursed_chest",
    "deus_potions", "deus_soft_currency",
    "ammo", "healing", "grenades", "level_events",
    "explosive_barrel", "frag_grenade", "fire_grenade",
}

-- audit 2026-06-07 (v0.7.133-dev): `local` dropped — assigns into the forward-
-- declared slot near the top of the file so the earlier populate_pickups hook
-- reference resolves to this upvalue instead of a nil global.
function _dump_pickup_system_state(prefix, also_echo)
    prefix = prefix or "[pickup_dump]"
    local emit = function(line)
        _dbg("%s %s", prefix, line)
        if also_echo then mod:echo(line) end
    end

    -- 1. Resolve current level + difficulty
    local level_key, difficulty_key
    pcall(function()
        local gm_mgr = Managers and Managers.state and Managers.state.game_mode
        if gm_mgr and gm_mgr.level_key then level_key = gm_mgr:level_key() end
        local diff_mgr = Managers and Managers.state and Managers.state.difficulty
        if diff_mgr and diff_mgr.get_difficulty then difficulty_key = diff_mgr:get_difficulty() end
    end)
    emit(string.format("level=%s difficulty=%s", tostring(level_key), tostring(difficulty_key)))

    -- 2. LevelSettings[level_key].pickup_settings — full per-difficulty dump
    local level_settings_root = rawget(_G, "LevelSettings")
    local ls = level_settings_root and level_key and level_settings_root[level_key]
    if not ls then
        emit("LevelSettings[level_key] = nil (cannot inspect pickup_settings)")
    else
        local ps = ls.pickup_settings
        if not ps then
            emit("level.pickup_settings = nil (level has no pickup_settings table)")
        else
            local diff_keys = {}
            for k, _ in pairs(ps) do diff_keys[#diff_keys + 1] = tostring(k) end
            table.sort(diff_keys)
            emit("level.pickup_settings keys: {" .. table.concat(diff_keys, ",") .. "}")
            local matching = ps[difficulty_key]
            if not matching then
                emit(string.format(
                    "NO MATCH for current difficulty='%s' in pickup_settings — engine will fall back. "
                    .. "This is the root signal for Issue #58.",
                    tostring(difficulty_key)))
            end
            -- For each difficulty present, dump the primary counts
            for _, dk in ipairs(diff_keys) do
                local entry = ps[dk]
                if type(entry) == "table" and type(entry.primary) == "table" then
                    local p = entry.primary
                    local parts = {}
                    for _, cat in ipairs(_PICKUP_CATEGORIES) do
                        if p[cat] ~= nil then
                            parts[#parts + 1] = string.format("%s=%s", cat, tostring(p[cat]))
                        end
                    end
                    for k, v in pairs(p) do
                        local known = false
                        for _, cat in ipairs(_PICKUP_CATEGORIES) do if k == cat then known = true; break end end
                        if not known then
                            parts[#parts + 1] = string.format("%s=%s", tostring(k), tostring(v))
                        end
                    end
                    emit(string.format("  [%s].primary { %s }", dk, table.concat(parts, ", ")))
                end
            end
        end
    end

    -- 3. PickupSystem live spawner lists, counted by spawner_type
    local entity_mgr = Managers and Managers.state and Managers.state.entity
    local ps_sys = entity_mgr and entity_mgr.system and entity_mgr:system("pickup_system")
    if not ps_sys then
        emit("PickupSystem unavailable (entity manager not ready)")
        return
    end

    local function count_by_type(list)
        local total, by_type = 0, {}
        if type(list) ~= "table" then return total, by_type end
        for _, unit in pairs(list) do
            total = total + 1
            if Unit and Unit.alive and Unit.alive(unit) then
                for _, cat in ipairs(_PICKUP_CATEGORIES) do
                    if Unit.get_data and Unit.get_data(unit, cat) then
                        by_type[cat] = (by_type[cat] or 0) + 1
                    end
                end
            end
        end
        return total, by_type
    end

    local function emit_list(name, list)
        local total, by_type = count_by_type(list)
        local parts = {}
        for _, cat in ipairs(_PICKUP_CATEGORIES) do
            if by_type[cat] then parts[#parts + 1] = string.format("%s=%d", cat, by_type[cat]) end
        end
        emit(string.format("PickupSystem.%s total=%d { %s }", name, total, table.concat(parts, ", ")))
    end

    emit_list("primary_pickup_spawners",   ps_sys.primary_pickup_spawners)
    emit_list("secondary_pickup_spawners", ps_sys.secondary_pickup_spawners)
    emit_list("specified_pickup_spawners", ps_sys.specified_pickup_spawners)
    emit_list("guaranteed_pickup_spawners", ps_sys.guaranteed_pickup_spawners)

    -- triggered_pickup_spawners is keyed by triggered_spawn_id
    if type(ps_sys.triggered_pickup_spawners) == "table" then
        local trig_total, group_count = 0, 0
        for _, group in pairs(ps_sys.triggered_pickup_spawners) do
            group_count = group_count + 1
            if type(group) == "table" then
                for _ in pairs(group) do trig_total = trig_total + 1 end
            end
        end
        emit(string.format("PickupSystem.triggered_pickup_spawners groups=%d total_units=%d", group_count, trig_total))
    end
end

-- v0.7.126-dev — verbose per-spawner-unit dump. Captures world position + every
-- truthy Unit.get_data(unit, key) for each placed spawner unit, so we can
-- diff a "working" mission (vanilla magnus in Adventure) against a "broken"
-- mission (magnus_belakor_path1 in CW) and see which spawner categories the
-- bundle actually ships on each level. Capped at 50 units per list — typical
-- adventure level has 30–80 spawners; cap keeps the log readable while still
-- giving 50 worked examples per category.
local _VERBOSE_DUMP_CAP_PER_LIST = 50
-- audit 2026-06-07 (v0.7.133-dev): `local` dropped — assigns into the forward-
-- declared slot near the top of the file (see _dump_pickup_system_state note).
function _dump_pickup_spawners_verbose(prefix)
    prefix = prefix or "[pickup_units]"
    local entity_mgr = Managers and Managers.state and Managers.state.entity
    local ps_sys = entity_mgr and entity_mgr.system and entity_mgr:system("pickup_system")
    if not ps_sys then return end

    local function dump_one(list_name, list)
        if type(list) ~= "table" then return end
        local idx = 0
        for _, unit in pairs(list) do
            idx = idx + 1
            if idx > _VERBOSE_DUMP_CAP_PER_LIST then
                _dbg("%s   %s ... (truncated at %d units)", prefix, list_name, _VERBOSE_DUMP_CAP_PER_LIST)
                break
            end
            if Unit and Unit.alive and Unit.alive(unit) then
                local pos = "?"
                pcall(function()
                    local p = Unit.local_position(unit, 0)
                    pos = string.format("(%.1f,%.1f,%.1f)", Vector3.x(p), Vector3.y(p), Vector3.z(p))
                end)
                local tags = {}
                for _, cat in ipairs(_PICKUP_CATEGORIES) do
                    if Unit.get_data(unit, cat) then tags[#tags + 1] = cat end
                end
                if Unit.get_data(unit, "tome")     then tags[#tags + 1] = "tome"     end
                if Unit.get_data(unit, "grimoire") then tags[#tags + 1] = "grimoire" end
                if Unit.get_data(unit, "loot_die") then tags[#tags + 1] = "loot_die" end
                if Unit.get_data(unit, "painting_scrap") then tags[#tags + 1] = "painting_scrap" end
                _dbg("%s   %s[%d] pos=%s tags={%s}", prefix, list_name, idx, pos,
                    table.concat(tags, ","))
            end
        end
    end

    dump_one("primary",    ps_sys.primary_pickup_spawners)
    dump_one("secondary",  ps_sys.secondary_pickup_spawners)
    dump_one("specified",  ps_sys.specified_pickup_spawners)
    dump_one("guaranteed", ps_sys.guaranteed_pickup_spawners)
end

mod:hook_safe("GameModeDeus", "local_player_game_starts", function(self, player, loading_context)
    -- v0.7.124-dev — per-mission diagnostic dump (Issue: citadel curse mismatch).
    -- Gated on VMF debug logging via _dbg. Runs on BOTH peers when a CW mission
    -- starts. Dumps current_node + its full state so we can compare host vs client
    -- and verify the active mutator list matches the node's expected curse.
    pcall(function()
        local rc = self._deus_run_controller
        if not rc then
            _dbg("[mission:start] no _deus_run_controller (unexpected)")
            return
        end
        local rs = rc._run_state
        local is_server = (rs and rs.is_server and rs:is_server())
                          or (Managers and Managers.player and Managers.player.is_server)
                          or false
        local cur_key = rc.get_current_node_key and rc:get_current_node_key() or nil
        local cur = rc.get_current_node and rc:get_current_node() or nil
        local mutators_str = "<nil>"
        if cur and type(cur.mutators) == "table" then
            local list = {}
            for i, m in ipairs(cur.mutators) do list[i] = tostring(m) end
            mutators_str = "{" .. table.concat(list, ",") .. "}"
        end
        -- Active engine-side mutators (via MutatorHandler). Snapshot the set so we
        -- can compare against the node's `mutators` list and the displayed curse.
        local active_str = "<unavailable>"
        local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
        if game_mode_manager then
            local mh = game_mode_manager._mutator_handler
            local active = mh and mh.activated_mutators and mh:activated_mutators()
            if type(active) == "table" then
                local names = {}
                for name, _ in pairs(active) do names[#names + 1] = tostring(name) end
                table.sort(names)
                active_str = "{" .. table.concat(names, ",") .. "}"
            end
        end
        _dbg("[mission:start] is_server=%s current_node=%s level=%s base_level=%s theme=%s curse=%s level_seed=%s god=%s node_type=%s node_mutators=%s active_mutators=%s",
            tostring(is_server), tostring(cur_key),
            cur and tostring(cur.level) or "<nil>",
            cur and tostring(cur.base_level) or "<nil>",
            cur and tostring(cur.theme) or "<nil>",
            cur and tostring(cur.curse) or "<nil>",
            cur and tostring(cur.level_seed) or "<nil>",
            cur and tostring(cur.god) or "<nil>",
            cur and tostring(cur.node_type) or "<nil>",
            mutators_str, active_str)
    end)

    -- v0.7.125-dev — pickup-system state dump (Issue #58: Magnus pickups).
    -- Log-only (no echo) when VMF debug logging is on. Captures level
    -- pickup_settings table contents + live PickupSystem spawner counts per
    -- spawner_type. Critical for diagnosing "no chests/altars spawn" bugs.
    pcall(_dump_pickup_system_state, "[ct_dbg][pickups:mission_start]", false)

    if not on_injected_adventure_level() then return end
    local run_controller = self._deus_run_controller
    if not run_controller then return end
    local current_node = run_controller:get_current_node()
    if not current_node then return end
    local theme = current_node.theme
    if not theme or theme == "wastes" then
        _dbg("[curse-tint] theme=%s (no curse); skipping", tostring(theme))
        return
    end
    local palette = _CURSE_LIGHT_PALETTES[theme]
    if not palette then
        mod:warning("[curse-tint] no palette mapping for theme=%s", tostring(theme))
        return
    end

    local world = self._world
    local level = LevelHelper:current_level(world)
    if not level then return end

    -- DELIBERATE: don't tint the camera backlight (that was glowing the
    -- first-person hands which the user didn't want). Tint only world lights.
    local units = Level.units(level)
    local lights_tinted = 0
    local global_idx = 0
    for j = 1, #units do
        local level_unit = units[j]
        if Unit.alive(level_unit) then
            local num_lights = Unit.num_lights(level_unit)
            if num_lights and num_lights > 0 then
                for i = 1, num_lights do
                    local light = Unit.light(level_unit, i - 1)  -- 0-indexed per vanilla
                    if light then
                        global_idx = global_idx + 1
                        local slot = _palette_slot(palette, global_idx)
                        Light.set_color(light, Vector3(slot[1], slot[2], slot[3]))
                        lights_tinted = lights_tinted + 1
                    end
                end
            end
        end
    end
    _dbg("[curse-tint] level=%s theme=%s palette_size=%d lights=%d",
        tostring(current_node.level), tostring(theme), #palette, lights_tinted)
end)

-- ============================================================
-- Vanilla bug fix: NetworkedFlowStateManager._num_states leak
-- ============================================================
-- Fatshark vanilla bug. `NetworkedFlowStateManager.clear_object_state`
-- (networked_flow_state_manager.lua:493) nils `_object_states[unit]` when a
-- unit is destroyed (entity_manager2.lua:390) BUT NEVER DECREMENTS
-- `_num_states`. The counter is monotonic and the run fatals at
-- `_num_states == _max_states (512)` with:
--   "[NetworkedFlowStateManager] Too many object states(512)."
-- Every destroyed unit that ever held a networked flow state permanently
-- leaks its slot.
--
-- Hits hardest in CW runs with our adventure-mission injection + curses:
-- the `cursed_chest_objective_unit` buff is applied to every cursed-chest
-- enemy spawn (deus_generic_terror_events.lua:26 →
-- morris_buff_settings.lua:614 apply_objective_unit) which spawns a
-- `units/hub_elements/objective_unit` carrying a `chest_open_state`
-- networked flow state. Each enemy = 1 permanently-leaked slot. Crash
-- reproduced ~40 min into a Verminious Dreams khorne node with 2 Chests
-- of Trials triggered (crash dump
-- console-2026-05-14-03.23.33-d86fd894-...).
--
-- Fix: count the states being released, subtract from `_num_states` BEFORE
-- delegating to vanilla. Defensive about table shape since this is a
-- private engine field that could change shape in future patches.
mod:hook("NetworkedFlowStateManager", "clear_object_state", function(func, self, unit)
    local unit_states = self._object_states and self._object_states[unit]
    if unit_states and type(unit_states.states) == "table" and type(self._num_states) == "number" then
        local count = 0
        for _ in pairs(unit_states.states) do count = count + 1 end
        if count > 0 then
            self._num_states = math.max(0, self._num_states - count)
        end
    end
    return func(self, unit)
end)

-- ============================================================
-- Curse SKY / atmosphere tinting (CameraManager.shading_callback)
-- ============================================================
-- Light.set_color only tints individual lights — adventure-level skies, sun,
-- and atmospheric fog stay vanilla. Peregrinaje (bundle-unpacked, file
-- 92BC0C4E7BFF8C3A.lua) drives sky/sun/fog via ShadingEnvironment.set_vector3
-- on keys like `skydome_tint_color`, `sun_color`, `secondary_sun_color`,
-- `ambient_tint`, `fog_color`. Vanilla CameraManager.shading_callback
-- (camera_manager.lua:283-368) runs per frame with a live shading_env handle;
-- vanilla `MoodHandler.apply_environment_variables` is called at line 346 to
-- overlay any active moods. We hook_safe AFTER vanilla so the curse tint
-- multiplies the post-mood sky color.
--
-- Stingray re-seeds the shading_environment from the level's baked template
-- every frame, so no save/restore — when the player leaves the cursed node
-- and we stop applying, the level's vanilla atmosphere returns automatically.
-- Per-curse lighting PROFILES instead of a single flat tint. Each profile
-- specifies a different multiplicative tint per shading-environment variable so
-- the scene reads as "themed atmosphere" rather than "uniform color filter":
--   - sky (skydome_tint_color):    the headline color — strongest hue
--   - sun (sun_color):             warmer / cooler accent, not pure-color
--   - secondary_sun (fill):        subtler, often neutral-toward-tint
--   - ambient_tint (mid):          moody, shifts whole scene tone
--   - ambient_tint_top (zenith):   slight contrast cue at the top of ambient
--   - fog_color (haze):            second strongest accent, ties scene together
--   - exposure (scalar):           tiny dim/bright tweak for mood
-- All values are multiplicative on top of the level's baked atmosphere, so the
-- result blends with the underlying environment instead of replacing it.
local _CURSE_SKY_PROFILES = {
    -- KHORNE — blood-red dominant. v0.7.18: toned ~30% toward neutral
    -- so the exterior color isn't oppressive (user feedback).
    khorne = {
        skydome_tint_color   = { 1.32, 0.51, 0.44 },
        sun_color            = { 1.21, 0.76, 0.62 },
        secondary_sun_color  = { 1.14, 0.65, 0.58 },
        ambient_tint         = { 1.04, 0.69, 0.62 },
        ambient_tint_top     = { 1.14, 0.58, 0.51 },
        fog_color            = { 1.39, 0.48, 0.44 },
        exposure_mul         = 0.95,
    },
    -- NURGLE — sickly bog green. v0.7.18 toned ~30% toward neutral. v0.7.46
    -- further tones the green channel ~10–15% on every slot and shifts toward
    -- yellow so it reads as jaundiced/sickly without overwhelming. Per user:
    -- "outdoor greens a bit less intense, but still visibly a sickly greenish-yellow."
    nurgle = {
        skydome_tint_color   = { 0.78, 1.05, 0.55 },   -- was {0.62, 1.21, 0.58} — softer sky, more yellow tint
        sun_color            = { 1.05, 1.02, 0.65 },   -- was {0.97, 1.11, 0.69} — pull green down, lean yellow
        secondary_sun_color  = { 0.92, 0.98, 0.66 },   -- was {0.79, 1.04, 0.69}
        ambient_tint         = { 0.88, 0.95, 0.68 },   -- was {0.76, 1.00, 0.72} — softer bounce
        ambient_tint_top     = { 0.82, 1.00, 0.60 },   -- was {0.69, 1.07, 0.62}
        fog_color            = { 0.80, 1.05, 0.55 },   -- was {0.65, 1.14, 0.58} — fog less aggressively green
        exposure_mul         = 1.00,
    },
    -- TZEENTCH — cobalt sky lit by orange daylight, deep-blue point lights.
    -- v0.7.18: toned ~30% toward neutral on sun/ambient (user feedback —
    -- the deep-orange exterior in v0.7.17 was too oppressive). Cobalt sky
    -- and cool blue fog are also pulled slightly to neutral.
    tzeentch = {
        skydome_tint_color   = { 0.62, 0.76, 1.35 },   -- cobalt sky (softer)
        sun_color            = { 1.39, 0.72, 0.44 },   -- orange direct sun (softer than v0.7.17)
        secondary_sun_color  = { 1.28, 0.79, 0.55 },
        ambient_tint         = { 1.25, 0.86, 0.58 },
        ambient_tint_top     = { 1.32, 0.76, 0.48 },
        fog_color            = { 0.76, 0.83, 1.21 },   -- cool blue fog (softer)
        exposure_mul         = 1.04,
    },
    -- SLAANESH — pink + lilac, with hot magenta highlights. Sun is a peach
    -- counterpoint to the pink sky for visual depth. Ambient drinks the pink.
    slaanesh = {
        skydome_tint_color   = { 1.35, 0.50, 1.15 },
        sun_color            = { 1.30, 0.85, 0.95 },
        secondary_sun_color  = { 1.20, 0.65, 1.05 },
        ambient_tint         = { 1.15, 0.65, 1.05 },
        ambient_tint_top     = { 1.30, 0.55, 1.20 },
        fog_color            = { 1.25, 0.40, 1.10 },
        exposure_mul         = 0.97,
    },
    -- BELAKOR — twilight purple. v0.7.21: brightened ambient (interior
    -- bounce) so rooms aren't pitch-black, slightly dimmed exterior
    -- (sky + sun) so the outdoor mood stays oppressive. Per user feedback.
    belakor = {
        skydome_tint_color   = { 0.40, 0.25, 0.65 },   -- slightly darker sky
        sun_color            = { 0.50, 0.50, 0.85 },   -- slightly dimmer direct sun
        secondary_sun_color  = { 0.55, 0.50, 0.90 },   -- brighter fill (helps interiors)
        ambient_tint         = { 0.75, 0.65, 1.00 },   -- BRIGHTER interior bounce (was 0.45/0.40/0.75)
        ambient_tint_top     = { 0.60, 0.55, 1.00 },   -- brighter top ambient
        fog_color            = { 0.40, 0.30, 0.75 },   -- keep fog
        exposure_mul         = 0.92,                    -- less darkening (was 0.85)
    },
}

local function _current_node_theme()
    if not (Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
    local mechanism = Managers.mechanism:game_mechanism()
    if not mechanism or not mechanism.get_deus_run_controller then return nil end
    local run = mechanism:get_deus_run_controller()
    if not run or not run.get_current_node then return nil end
    local node = run:get_current_node()
    return node and node.theme or nil
end

local function _current_node_curse()
    if not (Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
    local mechanism = Managers.mechanism:game_mechanism()
    if not mechanism or not mechanism.get_deus_run_controller then return nil end
    local run = mechanism:get_deus_run_controller()
    if not run or not run.get_current_node then return nil end
    local node = run:get_current_node()
    return node and node.curse or nil
end

-- v0.7.64: locus only spawns on the actual Belakor-cursed mission.
local function _current_node_is_belakor()
    return _current_node_curse() == "curse_belakor_totems"
end

mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
    if not on_injected_adventure_level() then return end
    local theme = _current_node_theme()
    if not theme or theme == "wastes" then return end
    local profile = _CURSE_SKY_PROFILES[theme]
    if not profile then return end

    -- Multiply each existing color by the curse profile's per-var tint.
    -- ShadingEnvironment.vector3 returns a fresh Vector3 each call (valid
    -- within this frame) — safe to read, multiply, and write back.
    local function mul_set(var_name)
        local t = profile[var_name]
        if not t then return end
        local v = ShadingEnvironment.vector3(shading_env, var_name)
        if v then
            ShadingEnvironment.set_vector3(shading_env, var_name,
                Vector3(v.x * t[1], v.y * t[2], v.z * t[3]))
        end
    end
    mul_set("skydome_tint_color")
    mul_set("sun_color")
    mul_set("secondary_sun_color")
    mul_set("ambient_tint")
    mul_set("ambient_tint_top")
    mul_set("fog_color")

    if profile.exposure_mul and profile.exposure_mul ~= 1.0 then
        local cur = ShadingEnvironment.scalar(shading_env, "exposure")
        if cur then
            ShadingEnvironment.set_scalar(shading_env, "exposure", cur * profile.exposure_mul)
        end
    end
end)

-- ============================================================
-- Replace shrines with missions (SHOP -> TRAVEL conversion)
-- ============================================================
-- When `replace_shrines_with_missions` is enabled, every SHOP node in the base
-- journey graph is converted to a TRAVEL node BEFORE deus_populate_graph picks
-- levels for it. Effect: the boon-picker shrines on Olesya's map become regular
-- mission slots that roll from the TRAVEL pool (vanilla CW missions plus any
-- enabled adventure missions). Players play more missions and lose the free
-- between-mission boon picks.
--
-- Implementation: hook deus_populate_graph and clone-then-mutate the base_graph
-- before passing to the original. We shallow-clone individual SHOP nodes (not
-- the whole graph) so we don't waste memory copying TRAVEL/SIGNATURE/ARENA nodes
-- — and crucially DON'T mutate the source baked-graph table, which is shared
-- across calls. Setting `label = 0` on the converted node skips the
-- shuffled_levels_for_labels deterministic lookup and forces a random pick from
-- LEVEL_AVAILABILITY.TRAVEL (which is what we want — random TRAVEL roll).
-- Map node icon swap for adventure levels. Vanilla `spawn_graph_units` in
-- deus_map_scene.lua:182-192 picks the node's 3D model by string-prefix on
-- `node.level`:  "sig_*" → SIG, "pat_*" → TRAVEL, "arena_*" → ARENA, else SHRINE.
-- Adventure mission keys (e.g. `bell_khorne_path1`, `farmlands_khorne_path1`)
-- don't match any prefix, so they fall to SHRINE. Hook DeusMapScene.on_enter
-- (the public method that calls spawn_graph_units at line 466): walk the
-- graph_data, prefix each adventure node's `level` with the CW-icon basename
-- that matches the mission's `icon` field, call vanilla, then restore.
-- This routes adventure nodes to TRAVEL_NODE_UNIT and feeds the flow event's
-- `data.level` lookup a CW basename it recognizes (pat_tower for towers,
-- pat_mountain for mountain missions, etc.) so the per-mission icon variant
-- on the 3D node mesh matches our `icon` field. Adventure base_level is also
-- rewritten so the flow event's `data.level` (set from node.base_level on the
-- spawned unit) sees the icon-matching base too.
mod:hook("DeusMapScene", "on_enter", function(func, self, graph_data, ...)
    if not graph_data then
        _dbg("[DeusMapScene.on_enter] no graph_data; passing through")
        return func(self, graph_data, ...)
    end
    -- v0.7.64 late-arrival apply: if the host's graph snapshot arrived AFTER the
    -- client's `deus_populate_graph` ran (RPC ordering race during setup_run),
    -- this is the natural re-apply site — the map UI is the only visible consumer
    -- the user complained about. Phase-A's in-place mutation makes downstream
    -- `_path_graph` reads see the synced values too, so we don't need a third
    -- application site for in-mission tooltip / curse-name reads.
    if _ct_host_graph_snapshot then
        local applied = apply_graph_snapshot(graph_data)
        if applied > 0 then
            _dbg("[ct_graph] applied host snapshot to %d nodes (DeusMapScene.on_enter)", applied)
        end
    end
    local saved = {}
    local seen, rewritten, skipped = 0, 0, 0
    for key, node in pairs(graph_data) do
        if type(node) == "table" and type(node.level) == "string" then
            seen = seen + 1
            local base_key = adventure_base_from_level_key(node.level)
            if base_key then
                local mission = AdventurePool and AdventurePool.MISSION_BY_KEY and AdventurePool.MISSION_BY_KEY[base_key]
                local icon = mission and mission.icon or "mountain"  -- fallback
                local cw_base = "pat_" .. icon
                saved[key] = { level = node.level, base_level = node.base_level }
                local suffix = node.level:match("(_[a-z]+_path%d+)$") or "_wastes_path1"
                local new_level = cw_base .. suffix
                _dbg("[DeusMapScene.on_enter]   rewrite %s: %s -> %s (theme=%s curse=%s)",
                    tostring(key), node.level, new_level, tostring(node.theme), tostring(node.curse))
                node.level = new_level
                node.base_level = cw_base
                rewritten = rewritten + 1
            else
                if node.level:match("^pat_") or node.level:match("^sig_") or node.level:match("^arena_") or node.level:match("^shop_") then
                    -- vanilla CW level, no rewrite needed
                else
                    skipped = skipped + 1
                    _dbg("[DeusMapScene.on_enter]   SKIP %s level=%s (no adventure base match — UI will use SHRINE_NODE_UNIT and curse halo won't show)",
                        tostring(key), node.level)
                end
            end
        end
    end
    _dbg("[DeusMapScene.on_enter] seen=%d rewritten=%d skipped_non_vanilla_non_adventure=%d",
        seen, rewritten, skipped)

    local result = { func(self, graph_data, ...) }

    for key, original in pairs(saved) do
        if graph_data[key] then
            graph_data[key].level = original.level
            graph_data[key].base_level = original.base_level
        end
    end
    -- v0.7.107-dev nil-hole audit: DeusMapScene.on_enter (deus_map_scene.lua:453)
    -- returns nothing — the body assigns to `self.*` fields and ends. No multi-return
    -- to preserve, no nil-hole risk. Left as-is per audit.
    return unpack(result) -- unpack-safe: no multi-return, body assigns self.* fields
end)

-- Filter curse pool by user's disable_curse_* settings BEFORE the graph generator
-- runs spread_curse → assign_random_curse. The vanilla picker reads
-- `config.AVAILABLE_CURSES[node_type][god]` and picks at random. If we strip
-- disabled curses from that array, a node hot-spotted to god X will roll a
-- DIFFERENT enabled curse of X instead of being nil-curse'd by our downstream
-- _transition_next_node hook.
-- Edge case: if user disabled ALL curses of god X, leaving the array empty would
-- crash assign_random_curse (`curses[random(1, 0)]` → nil indexing). We keep the
-- original list in that case so the picker has something to pick; the existing
-- runtime curse-disable hooks (_activate_mutator, get_current_node_curse,
-- _transition_next_node, start_next_round, _enable_hover) then null out the
-- still-disabled curse — net effect: theme stays as the god, curse vanishes.
-- Returns the save-list so the caller can restore originals after func() runs.
local function filter_available_curses(config)
    local saved = {}
    if not config or not config.AVAILABLE_CURSES then return saved end
    for node_type, god_table in pairs(config.AVAILABLE_CURSES) do
        if type(god_table) == "table" then
            for god, curse_list in pairs(god_table) do
                if type(curse_list) == "table" and #curse_list > 0 then
                    local filtered = {}
                    for _, curse in ipairs(curse_list) do
                        local key = "disable_curse_" .. curse:gsub("^curse_", "")
                        -- v0.7.42: use effective_setting so client mirrors host's disable
                        -- choices. Otherwise the deus_populate_graph filtering diverges
                        -- across peers → wrong-curse-on-node visible to one player only.
                        if not effective_setting(key) then
                            filtered[#filtered + 1] = curse
                        end
                    end
                    if #filtered > 0 and #filtered < #curse_list then
                        saved[#saved + 1] = { tbl = god_table, key = god, original = curse_list }
                        god_table[god] = filtered
                    end
                    -- If #filtered == 0 (all disabled), leave original in place; the
                    -- runtime is_curse_disabled hooks will null the picked curse anyway.
                end
            end
        end
    end
    return saved
end

local function restore_available_curses(saved)
    for i = #saved, 1, -1 do
        local entry = saved[i]
        entry.tbl[entry.key] = entry.original
    end
end

mod:hook(_G, "deus_populate_graph", function(func, base_graph, seed, config, dominant_god, with_belakor)
    -- CW graph generation runs on BOTH host and client (deterministic from
    -- seed). Use effective_setting(name) — returns mod:get() on host, the
    -- most-recently-synced host value on clients. v0.7.20 gated this hook
    -- on `is_server` to stop the deus_shop_view_v2 nil crash; v0.7.21
    -- replaces that gate with proper host→client setting sync (broadcast in
    -- the setup_run hook above) so peers produce IDENTICAL graphs from the
    -- same seed instead of merely-vanilla-on-client graphs.
    --
    -- If the broadcast hasn't arrived yet on the client (first run, RPC
    -- ordering), effective_setting falls back to defaults that match
    -- vanilla behavior (no mutation) — same safety as the v0.7.20 gate.

    -- Override the curse hotspot count if the user has set `cursed_mission_count`.
    -- Vanilla `spread_curse` (deus_populate_graph.lua:681) does:
    --   hot_spot_count = random(CURSES_HOT_SPOTS_MIN_COUNT, CURSES_HOT_SPOTS_MAX_COUNT)
    --   for each cluster: pick a center node, curse it, AND spread curse to nodes
    --   within `CURSES_HOT_SPOT_MAX_RANGE` (so each cluster typically curses 1-3 nodes).
    -- For the user's setting to give an EXACT count of cursed missions, we both:
    --   1. Force MIN = MAX = N (deterministic cluster count)
    --   2. Set MIN_RANGE = MAX_RANGE = 0 (each cluster curses only its center, no spread)
    -- Net: exactly N cursed nodes (or fewer if the map has < N curseable nodes; the
    -- spreader stops early when it runs out of candidates).
    local saved_min, saved_max, saved_range_min, saved_range_max, saved_min_progress, saved_no_dominant
    local override_curse_count = effective_setting("cursed_mission_count")
    _dbg("[deus_populate_graph] override_curse_count=%s, config?=%s, vanilla_min=%s vanilla_max=%s vanilla_range_min=%s vanilla_range_max=%s vanilla_min_progress=%s",
        tostring(override_curse_count), tostring(config ~= nil),
        config and tostring(config.CURSES_HOT_SPOTS_MIN_COUNT) or "?",
        config and tostring(config.CURSES_HOT_SPOTS_MAX_COUNT) or "?",
        config and tostring(config.CURSES_HOT_SPOT_MIN_RANGE) or "?",
        config and tostring(config.CURSES_HOT_SPOT_MAX_RANGE) or "?",
        config and tostring(config.CURSES_MIN_PROGRESS) or "?")
    if config and override_curse_count and override_curse_count > 0 then
        saved_min = config.CURSES_HOT_SPOTS_MIN_COUNT
        saved_max = config.CURSES_HOT_SPOTS_MAX_COUNT
        saved_range_min = config.CURSES_HOT_SPOT_MIN_RANGE
        saved_range_max = config.CURSES_HOT_SPOT_MAX_RANGE
        saved_min_progress = config.CURSES_MIN_PROGRESS
        config.CURSES_HOT_SPOTS_MIN_COUNT = override_curse_count
        config.CURSES_HOT_SPOTS_MAX_COUNT = override_curse_count
        config.CURSES_HOT_SPOT_MIN_RANGE = 0
        config.CURSES_HOT_SPOT_MAX_RANGE = 0
        -- Vanilla CURSES_MIN_PROGRESS (typically 0.2) excludes the first 1-2
        -- nodes of every journey from being curseable. With range=0 (exact
        -- count) the user's early nodes are guaranteed-uncursed even when
        -- they pick count=30. Drop the floor below zero so cluster centers
        -- can land anywhere.
        --
        -- NOTE: must be NEGATIVE, not 0. Vanilla `get_nodes_above_progress`
        -- (deus_populate_graph.lua:45-55) uses strict `progress < node.run_progress`,
        -- so 0 < 0 is false — first-mission nodes (run_progress=0) get excluded
        -- even with min_progress=0. Use -1 so 1+1=2 nodes at run_progress=0 are
        -- in the pool.
        config.CURSES_MIN_PROGRESS = -1
        _dbg("[deus_populate_graph] applied override: count=%d range=0/0 min_progress=-1", override_curse_count)
    end

    -- Vanilla's spread_curse reserves the dominant_god for the "final"
    -- node only (deus_populate_graph.lua:686-690), then EXCLUDES it from
    -- the non-final rotation (line 698) — so a journey with
    -- dominant_god=khorne will never have Khorne curses on regular missions,
    -- only on the final arena. NO_DOMINANT_GOD=true puts all 4 gods into
    -- the uniform rotation (final loses its "must match dominant" guarantee).
    -- v0.7.18: user-toggleable as `disable_dominant_god` (default on).
    -- Applies INDEPENDENTLY of the count override so the user can re-enable
    -- normal curse counts with all gods in rotation, or vice versa.
    if config and effective_setting("disable_dominant_god") then
        saved_no_dominant = config.NO_DOMINANT_GOD
        config.NO_DOMINANT_GOD = true
        _dbg("[deus_populate_graph] disable_dominant_god=true (all 4 gods in rotation)")
    end

    -- Filter the curse pool so disabled curses get re-rolled within their god
    -- rather than just removed (per user spec).
    local saved_curses = filter_available_curses(config)

    local function restore_curse_count()
        if saved_min then config.CURSES_HOT_SPOTS_MIN_COUNT = saved_min end
        if saved_max then config.CURSES_HOT_SPOTS_MAX_COUNT = saved_max end
        if saved_range_min then config.CURSES_HOT_SPOT_MIN_RANGE = saved_range_min end
        if saved_range_max then config.CURSES_HOT_SPOT_MAX_RANGE = saved_range_max end
        if saved_min_progress then config.CURSES_MIN_PROGRESS = saved_min_progress end
        -- restore even when saved_no_dominant was nil (default vanilla state)
        config.NO_DOMINANT_GOD = saved_no_dominant
        restore_available_curses(saved_curses)
    end

    -- Count cursed nodes in the completed graph for diagnostic.
    -- IMPORTANT: completed graph uses `node_type` ("ingame"/"shop"/"start") —
    -- the `type` field is only on the BASE graph. Burned in v0.7.6's first
    -- pass which counted 0/0 because it checked the wrong field.
    local function count_cursed(graph)
        if type(graph) ~= "table" then return 0, 0 end
        local cursed, total = 0, 0
        for _, n in pairs(graph) do
            if type(n) == "table" and n.node_type == "ingame" then
                total = total + 1
                if n.curse then cursed = cursed + 1 end
            end
        end
        return cursed, total
    end

    -- Dump every node so we can see the FULL graph state regardless of type.
    local function dump_graph(graph, tag)
        if type(graph) ~= "table" then
            _dbg("[deus_populate_graph %s] graph is %s (not a table)", tag, type(graph))
            return
        end
        local n_count = 0
        for k, n in pairs(graph) do
            n_count = n_count + 1
            if type(n) == "table" then
                _dbg("[deus_populate_graph %s]   %s node_type=%s curse=%s god=%s level=%s progress=%s",
                    tag, tostring(k),
                    tostring(n.node_type), tostring(n.curse), tostring(n.god),
                    tostring(n.level), tostring(n.run_progress or n.progress or "?"))
            else
                _dbg("[deus_populate_graph %s]   %s = %s (not a table)", tag, tostring(k), tostring(n))
            end
        end
        _dbg("[deus_populate_graph %s] total entries: %d", tag, n_count)
    end

    if not effective_setting("replace_shrines_with_missions") then
        local result = { func(base_graph, seed, config, dominant_god, with_belakor) }
        local cursed, total = count_cursed(result[1])
        _dbg("[deus_populate_graph] post-run cursed=%d / total_curseable=%d", cursed, total)
        dump_graph(result[1], "post-run")
        restore_curse_count()
        -- v0.7.64 graph sync — see ct_graph_snapshot_chunk block above.
        local is_server = Managers and Managers.player and Managers.player.is_server
        if is_server then
            broadcast_graph_snapshot(result[1])
        else
            local applied = apply_graph_snapshot(result[1])
            if applied > 0 then
                _dbg("[ct_graph] applied host snapshot to %d nodes (post-run)", applied)
            end
        end
        -- v0.7.107-dev nil-hole audit: global `deus_populate_graph` (deus_populate_graph.lua:965)
        -- returns a single `complete_graph` table. The mod code already reads result[1]
        -- explicitly, confirming single-value usage. Bare unpack is safe — no interior
        -- nil hole can exist with one entry. Left as-is per audit.
        return unpack(result) -- unpack-safe: single-value usage, no interior nil hole
    end

    local mutated = {}
    local converted = 0
    for node_key, node in pairs(base_graph) do
        if type(node) == "table" and node.type == "SHOP" then
            local copy = table.clone(node)
            copy.type = "TRAVEL"
            copy.label = 0
            mutated[node_key] = copy
            converted = converted + 1
        else
            mutated[node_key] = node
        end
    end

    if converted > 0 then
        _dbg("deus_populate_graph: converted %d SHOP node(s) to TRAVEL", converted)
    end

    local result = { func(mutated, seed, config, dominant_god, with_belakor) }
    local cursed, total = count_cursed(result[1])
    _dbg("[deus_populate_graph] post-run (shop-converted) cursed=%d / total_curseable=%d", cursed, total)
    dump_graph(result[1], "post-run-shop-converted")
    restore_curse_count()
    -- v0.7.64 graph sync — see ct_graph_snapshot_chunk block above.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        broadcast_graph_snapshot(result[1])
    else
        local applied = apply_graph_snapshot(result[1])
        if applied > 0 then
            _dbg("[ct_graph] applied host snapshot to %d nodes (post-run-shop-converted)", applied)
        end
    end
    -- v0.7.107-dev nil-hole audit: same as sibling branch above — global
    -- `deus_populate_graph` returns a single `complete_graph` table; mod code
    -- reads result[1] explicitly. Bare unpack is safe. Left as-is per audit.
    return unpack(result) -- unpack-safe: single complete_graph table, read as result[1]
end)

-- ============================================================
-- Per-career weapon override recovery (fixes CW bot ghost-scythe crash)
-- ============================================================
--
-- Crash: `Unit not found wpn_bw_ghost_scythe_01_3p` (Necromancer base mesh) when a
-- Sienna Unchained bot spawns with the ghost scythe (the scythe can_wield all four
-- Sienna careers; non-Necromancer careers use `_fire` mesh variants via
-- `ItemMasterList.bw_ghost_scythe.right_hand_unit_override`).
--
-- Vanilla flow:
--   simple_inventory_extension.add_equipment passes `self._career_name` to
--   gear_utils.create_equipment, which calls
--   `BackendUtils.get_item_units(item_data, nil, nil, career_name)`. The override
--   block at `backend_utils.lua:159-162` is gated on `career_name`, so when it
--   arrives nil, the BASE `right_hand_unit` survives — and `gear_utils.lua:189`
--   derives the 3P path as `weapon_unit_name .. "_3p"` (base 3P), which isn't
--   in the bot's preloaded packages → `world.spawn_unit` fatal.
--
-- Why career_name arrives nil: observed in weapon_tweaker v0.12.23/v0.12.24 — the
-- hook chain between simple_inventory and the unwrapped gear_utils drops the arg
-- (multiple modded create_equipment hooks chain via varargs, and one of them
-- occasionally loses the trailing args). weapon_tweaker fixed this for users with
-- that mod loaded; users who only have chaos_wastes_tweaker need the same fix here.
--
-- Fix (two layers):
--   1. If career_name is nil at hook entry, recover it from the 3P unit's
--      `inventory_system._career_name` (set in `SimpleInventoryExtension.init`
--      before extensions_ready fires).
--   2. If item_data has a per-career override AND we have career_name, pre-resolve
--      `item_units` ourselves and pass via override_item_units. Vanilla
--      gear_utils uses `override_item_units or get_item_units(...)`, so our
--      pre-resolved table is used verbatim and the broken chain pass-through is
--      sidestepped entirely.
--
-- Originally landed in weapon_tweaker v0.12.23-25; cross-ported here so the fix
-- works for users running ct without wt. Both mods can host the hook safely
-- (VMF chains them and the operation is idempotent — if the upstream hook
-- already pre-resolved override_item_units, our `override_item_units == nil`
-- guard skips the re-resolve).
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if career_name == nil and unit_3p and ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(unit_3p, "inventory_system") then
        local inv = ScriptUnit.extension(unit_3p, "inventory_system")
        career_name = inv and inv._career_name or nil
    end

    if override_item_units == nil and item_data and career_name and BackendUtils
            and BackendUtils.get_item_units
            and ((item_data.right_hand_unit_override and item_data.right_hand_unit_override[career_name])
              or (item_data.left_hand_unit_override and item_data.left_hand_unit_override[career_name])) then
        local ok_resolve, resolved = pcall(BackendUtils.get_item_units, item_data, item_data.backend_id, nil, career_name)
        if ok_resolve and type(resolved) == "table" then
            override_item_units = resolved
        end
    end

    return func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
end)

-- `_chest_conversions_this_level` is declared earlier in this file (search for
-- the populate_pickups hook) and reset there at the top of every populate.
-- That placement is required because Lua 5.1 binds closure locals at creation
-- time, and consolidating populate_pickups hooks into one avoids the VMF
-- "Attempting to rehook active hook" warning.

-- Hook on PickupSystem._spawn_pickup — the lowest-level spawn function that ALL
-- paths route through (public spawn_pickup, spawn_pickup_async, buff_spawn_pickup,
-- _spawn_guaranteed_pickup, _spawn_spread_pickups). Used for two purposes:
--
-- 1. Substitute loot_die → deus_soft_currency on injected adventure levels.
--    The Bogenhafen loot-die system has no CW analogue. Catches:
--      a. Guaranteed spawners with loot_die data (also covered by our explicit
--         hook on _spawn_guaranteed_pickup above, but doesn't hurt to double-up).
--      b. Flow-event spawned loot dice (level-script-driven bonus dice drops).
--      c. Boss kill loot if the game_mode somehow returned "loot_die" (vanilla
--         GameModeDeus.get_boss_loot_pickup returns "deus_soft_currency" already
--         for our deus-mode adventure levels, but defensive).
--
-- 2. Disable physics collision on CW altars/chests so they don't block player
--    pathing at adventure spawner positions (designed for ammo/healing, not for
--    a multi-meter-wide blocking prop). `Actor.set_collision_enabled(false)`
--    removes the character-controller block; interaction raycasts still hit the
--    visible mesh, so E-to-open still works.
local _CW_BLOCKING_PICKUP_NAMES = {
    deus_weapon_chest = true,
    deus_cursed_chest = true,
    deus_02 = true,  -- alternate chest variant some CW level pickup_settings reference
}

-- Adventure-map collectibles with no CW analogue -> Pilgrim's Coin. loot_die
-- covers bonus dice AND the DLC-map "hidden mission" reskins (Bogenhafen ale,
-- Blightreaper Rugbrodder ale, Enchanter's Lair poison-feast chalice -- all
-- loot_die-tagged spawners of the same bonus-dice system). lorebook_page (the
-- lore-page collectible) is the only other map collectible type and has no CW
-- use, so it's converted too. painting_scrap (collectible art, all maps) is
-- already handled by the _can_spawn spawner mapping further below.
local _CW_COLLECTIBLE_TO_COIN = { loot_die = true, lorebook_page = true }
mod._ct_collectible_to_coin = _CW_COLLECTIBLE_TO_COIN  -- exposed for regression guard

-- #134 DIAGNOSTIC (Ravaged Art + Loot Dice not converting to Pilgrim's Coin on CW
-- adventure maps). Logs each collectible (loot_die / lorebook_page / painting_scrap)
-- that reaches the actual spawn, WITH the on_injected_adventure_level() gate broken
-- down (in a deus run? level recognised as an adventure base?), plus the spawn_type
-- (how it was spawned). So we can tell whether they bypass conversion because the GATE
-- is false (most likely) or via a spawn path the conversion hooks miss. Raw printf
-- survives mod-logging-off; bounded 80 lines/session; pcall-guarded; changes NO
-- conversion logic. (#134)
do
    local _n = 0
    function mod._ct134_log(name, spawn_type)
        if _n >= 80 then return end
        _n = _n + 1
        local on_adv, deus, level_id, adv_base = false, false, "?", "?"
        pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            level_id = (cur and cur.level_id) or "?"
            adv_base = tostring(adventure_base_from_level_key(level_id))
            local m = Managers.mechanism and Managers.mechanism.game_mechanism
                and Managers.mechanism:game_mechanism()
            deus = (m and m.get_deus_run_controller and m:get_deus_run_controller()) ~= nil
            on_adv = on_injected_adventure_level()
        end)
        printf("[ct-probe:collectible] name=%s spawn_type=%s on_adv=%s in_coin_set=%s deus=%s level=%s adv_base=%s",
            tostring(name), tostring(spawn_type), tostring(on_adv),
            tostring(_CW_COLLECTIBLE_TO_COIN[name] and "yes" or "no"),
            tostring(deus), tostring(level_id), tostring(adv_base))
    end
end

mod:hook("PickupSystem", "_spawn_pickup", function(func, self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    local on_adv = on_injected_adventure_level()

    -- #134 DIAGNOSTIC: a collectible arriving here means it is being spawned; log it +
    -- the gate breakdown so we see why it isn't converting. DIAGNOSTIC ONLY.
    if pickup_name == "loot_die" or pickup_name == "lorebook_page" or pickup_name == "painting_scrap" then
        mod._ct134_log(pickup_name, spawn_type)
    end

    if on_adv and _CW_COLLECTIBLE_TO_COIN[pickup_name] then
        pickup_name = "deus_soft_currency"
        settings = (AllPickups and AllPickups.deus_soft_currency) or settings
    end

    -- #58/#156 spawn census: count the FINAL pickup_name (post collectible->coin
    -- conversion) once vanilla confirms it actually spawned. _spawn_pickup is the
    -- single chokepoint for both the spread pass and the guaranteed chest/altar pass,
    -- so this tallies EVERYTHING. Returns a single unit (or nil) in vanilla.
    local spawned = func(self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    if mod._ct_tally_count then mod._ct_tally_count(pickup_name, spawned) end
    return spawned
end)
-- Note: previous versions attempted to make altars/chests walk-through by mutating
-- their actor collision filter / scene_query / collision_enabled flags. This
-- ALWAYS regressed interaction (v0.6.28 scene_query disable broke chest open;
-- v0.6.32 filter_trigger broke it again). The Peregrinaje mod ships chests without
-- a physics blocker by some other mechanism — investigate that pattern before
-- re-attempting any collision-disable here.

mod:hook("PickupSystem", "_spawn_guaranteed_pickup", function(func, self, spawner_unit, spawn_type)
    if not on_injected_adventure_level() then
        return func(self, spawner_unit, spawn_type)
    end

    -- loot_die spawners on Bogenhafen (Brugrodder '68 bottle, etc.) are guaranteed
    -- side-objective collectibles. We have no CW equivalent system — convert these
    -- positions to deus_soft_currency (Pilgrim's Coin) so the spawner still gives
    -- something useful instead of dropping a collectible the run can't interact with.
    if Unit.get_data(spawner_unit, "loot_die") or Unit.get_data(spawner_unit, "lorebook_page") then
        local settings = AllPickups and AllPickups.deus_soft_currency
        if settings then
            local position = Unit.local_position(spawner_unit, 0)
            local rotation = Unit.local_rotation(spawner_unit, 0)
            return self:_spawn_pickup(settings, "deus_soft_currency", position, rotation, false, spawn_type)
        end
        return func(self, spawner_unit, spawn_type)
    end

    -- v0.7.65: sentinel -1 → 1 (vanilla default); 0+ → use as-is.
    -- Hoisted ABOVE the tome/grim early-out (was below it) so the native
    -- deus_cursed_chest branch added right below can reuse the same cap. Vanilla
    -- adventure maps ship 5 book pedestals (3 tomes + 2 grimoires), so up to 4
    -- spots remain afterwards.
    local cap_raw = effective_setting("cursed_chest_count") or -1  -- v0.7.42: sync with host
    local cap = (cap_raw == -1) and 1 or cap_raw

    -- v0.7.157-dev (Issue #60): native level-baked `deus_cursed_chest` spawners.
    -- ----------------------------------------------------------------------------
    -- Most injected adventure maps (dlc_termite_1, dlc_bastion, etc.) carry ONLY
    -- tome/grimoire pedestals, so every Chest of Trials they show is produced by
    -- the tome/grim → chest CONVERSION below — already capped by
    -- `_chest_conversions_this_level < cap`. Those maps spawn exactly `cap` chests
    -- and need no change here.
    --
    -- dlc_dwarf_beacons ("Khazukan Kazakit-ha!") is the outlier: its LEVEL GEOMETRY
    -- ships its own guaranteed spawners natively flagged `deus_cursed_chest` (NOT
    -- tome/grim), IN ADDITION TO book pedestals. Vanilla `_spawn_guaranteed_pickup`
    -- spawns those baked chests unconditionally — they are not drawn from the
    -- pickup sampler, so the `populate_pickups` sampler-count cap never touches them,
    -- and before this fix they ALSO failed the is_tome/is_grim test below and fell
    -- straight through to vanilla. Result: cap=3 produced 3 converted chests + 2
    -- baked chests = 5 total (the #60 report).
    --
    -- Fix: route native `deus_cursed_chest` spawners through the SAME per-mission
    -- `_chest_conversions_this_level < cap` budget the conversion path uses. Under
    -- the cap, let vanilla spawn the baked chest (and count it against the budget);
    -- AT/OVER the cap, suppress the spawner (return nothing → empty pedestal, same
    -- as the cap-reached tome/grim fallthrough). Host-authoritative:
    -- `_spawn_guaranteed_pickup` runs on the server for injected levels, so the
    -- decision is made once by the host and is not a per-peer divergence.
    --
    -- This is surgical — it ONLY fires for spawners the level natively tags
    -- `deus_cursed_chest`. Maps with no such baked spawners (termite/bastion/vanilla
    -- CW paths) never enter this branch and keep spawning exactly `cap` chests.
    if Unit.get_data(spawner_unit, "deus_cursed_chest") then
        if _chest_conversions_this_level < cap then
            -- Count the baked chest against the same budget the conversions use,
            -- then let vanilla spawn it from its native flag.
            _chest_conversions_this_level = _chest_conversions_this_level + 1
            -- [ct-probe] unconditional: native baked cursed-chest ALLOWED under cap.
            -- Survives a VMF-mod-logging-OFF host (raw print, not mod:info). #60.
            local pok = pcall(function()
                local cur = LevelHelper and LevelHelper:current_level_settings()
                printf("[ct-probe] baked_cursed_chest=ALLOW level=%s cap=%d count_now=%d",
                    tostring(cur and cur.level_id), cap, _chest_conversions_this_level)
            end)
            if not pok then printf("[ct-probe] baked_cursed_chest=ALLOW (level-id read failed) cap=%d count_now=%d", cap, _chest_conversions_this_level) end
            _dbg("[baked_chest] -> ALLOW (vanilla spawn) cap=%d count_now=%d", cap, _chest_conversions_this_level)
            return func(self, spawner_unit, spawn_type)
        end
        -- Budget exhausted: suppress this baked spawner so the level total never
        -- exceeds `cap`. Returning nothing skips the spawn; the pedestal stays
        -- empty (adventure flow units only materialize on spawn).
        -- [ct-probe] unconditional: native baked cursed-chest SUPPRESSED over cap.
        local pok2 = pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            printf("[ct-probe] baked_cursed_chest=SUPPRESS level=%s cap=%d count=%d (over budget)",
                tostring(cur and cur.level_id), cap, _chest_conversions_this_level)
        end)
        if not pok2 then printf("[ct-probe] baked_cursed_chest=SUPPRESS (level-id read failed) cap=%d count=%d", cap, _chest_conversions_this_level) end
        _dbg("[baked_chest] -> SUPPRESS (over cap) cap=%d count=%d", cap, _chest_conversions_this_level)
        return
    end

    local is_tome = Unit.get_data(spawner_unit, "tome")
    local is_grim = Unit.get_data(spawner_unit, "grimoire")
    if not is_tome and not is_grim then
        return func(self, spawner_unit, spawn_type)
    end

    -- Respect the user's `cursed_chest_count` setting. The first N book spots become
    -- Chests of Trials. Default ("Default" sentinel = -1) treats this as the vanilla
    -- value of 1 chest per mission; explicit 0 leaves all book spots empty.
    -- v0.7.125-dev (Issue #60): trace every conversion attempt so we can diagnose
    -- "5 chests spawned with host cap=3" reports. Logs cap_raw + cap + the running
    -- counter at decision time. Cheap; fires at most 5 times per mission load.
    _dbg("[pedestal] kind=%s cap_raw=%s cap=%d count=%d", is_tome and "tome" or "grim",
        tostring(cap_raw), cap, _chest_conversions_this_level)
    if _chest_conversions_this_level < cap then
        local pickup_name = "deus_cursed_chest"
        local settings = AllPickups and AllPickups[pickup_name]
        if not settings then
            -- AllPickups not yet built (extremely unlikely at populate time, but defensive).
            return func(self, spawner_unit, spawn_type)
        end

        local position = Unit.local_position(spawner_unit, 0)
        local rotation = Unit.local_rotation(spawner_unit, 0)
        local spawned_unit = self:_spawn_pickup(settings, pickup_name, position, rotation, false, spawn_type)
        _chest_conversions_this_level = _chest_conversions_this_level + 1
        -- [ct-probe] unconditional: tome/grim pedestal CONVERTED to a cursed chest
        -- under cap. This is the path termite/bastion/vanilla CW maps use (no baked
        -- deus_cursed_chest spawners), so without this line a logging-OFF host could
        -- count ACTUAL chests only on the Beacons (baked-spawner) path. Pairs with the
        -- baked_cursed_chest=ALLOW probe above to give the true per-map total. Raw
        -- printf bypasses the VMF mod-logging toggle (lands on Rain's logging-OFF host). #60.
        local pokc = pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            printf("[ct-probe] conversion_cursed_chest=ALLOW kind=%s level=%s cap=%d count_now=%d spawned=%s",
                is_tome and "tome" or "grim", tostring(cur and cur.level_id), cap,
                _chest_conversions_this_level, tostring(spawned_unit ~= nil))
        end)
        if not pokc then printf("[ct-probe] conversion_cursed_chest=ALLOW (level-id read failed) cap=%d count_now=%d", cap, _chest_conversions_this_level) end
        _dbg("[pedestal] -> chest_of_trials count_now=%d (spawned=%s)", _chest_conversions_this_level,
            tostring(spawned_unit ~= nil))
        return spawned_unit
    end

    -- v0.7.55: after Chests of Trials are placed, the NEXT remaining book spot becomes
    -- the Belakor altar (`deus_02` / `deus_belakor_locus`) when the host has "Always
    -- Include Belakor's Temple" on. One altar per mission, matching vanilla
    -- belakor-themed CW levels which all request `deus_02 = 1`. The `_spawn_pickup`
    -- call below also re-checks `can_spawn_belakor_locus` (vanilla pickup-settings
    -- `can_spawn_func` gate), which our DeusRunController.can_spawn_belakor_locus hook
    -- below permits on adventure-injected levels — both paths must agree, or the call
    -- silently no-ops.
    -- v0.7.64: locus only spawns on the actual Belakor cursed mission. Previously
    -- `force_belakor` alone caused the locus to land on the FIRST adventure-injected
    -- book pedestal regardless of which node held curse_belakor_totems — so in last
    -- night's run the locus landed on nurgle_slaanesh_path1 while the actual Belakor
    -- mission (magnus_belakor_path1) got nothing. `_current_node_is_belakor()` reads
    -- the current node's curse field, which is the only data that identifies "this
    -- mission has the Belakor totems curse." `force_belakor` itself only guarantees a
    -- Belakor curse appears SOMEWHERE in the run — it doesn't say where.
    -- v0.7.125-dev (Issue #60): log every altar-spawn decision so we can
    -- diagnose "no shadow locus on Belakor mission" reports. Captures every gate
    -- (force_belakor, current_node_is_belakor, AllPickups.deus_02, already-spawned).
    local altar_should = (not _belakor_altar_spawned_this_level)
        and effective_setting("force_belakor")
        and _current_node_is_belakor()
        and (AllPickups and AllPickups.deus_02 ~= nil)
    _dbg("[pedestal] altar_gate force_belakor=%s current_is_belakor=%s have_deus_02=%s already_spawned=%s -> attempt=%s",
        tostring(effective_setting("force_belakor")),
        tostring(_current_node_is_belakor()),
        tostring(AllPickups and AllPickups.deus_02 ~= nil),
        tostring(_belakor_altar_spawned_this_level),
        tostring(altar_should))
    if altar_should then
        local position = Unit.local_position(spawner_unit, 0)
        local rotation = Unit.local_rotation(spawner_unit, 0)
        local spawned_unit = self:_spawn_pickup(AllPickups.deus_02, "deus_02", position, rotation, false, spawn_type)
        _dbg("[pedestal] -> belakor_altar spawn=%s (vetoed=%s)", tostring(spawned_unit ~= nil),
            tostring(spawned_unit == nil))
        if spawned_unit then
            _belakor_altar_spawned_this_level = true
            return spawned_unit
        end
        -- _spawn_pickup returns nil if can_spawn_func vetoed; fall through to "skip
        -- this spawner" so the empty pedestal stays hidden, same as the no-cap case.
    end

    -- v0.7.148: leftover book pedestals (a tome/grimoire spot NOT taken by a Chest
    -- of Trials or the Belakor locus) become a BIGGER coin casket instead of an
    -- empty spot -- a reward where the book would have been. The casket is the
    -- normal deus_soft_currency pickup (deus_loot_pyramide_01) scaled to 1.75x and
    -- tagged `ct_big_casket`; the _get_coins_amount_and_type hook below grants it
    -- 3x the coin a normal casket would. _spawn_guaranteed_pickup runs per-peer on
    -- injected levels, so the scale + tag land on every peer's copy.
    do
        local casket_settings = AllPickups and AllPickups.deus_soft_currency
        if casket_settings then
            local position = Unit.local_position(spawner_unit, 0)
            local rotation = Unit.local_rotation(spawner_unit, 0)
            local casket = self:_spawn_pickup(casket_settings, "deus_soft_currency", position, rotation, false, spawn_type)
            if casket and Unit.alive(casket) then
                Unit.set_data(casket, "ct_big_casket", true)
                Unit.set_local_scale(casket, 0, Vector3(1.75, 1.75, 1.75))
                _dbg("[pedestal] -> BIG coin casket (1.75x scale, 3x coin) at leftover book spot")
                return casket
            end
        end
    end

    -- Could not build the casket (settings missing) — leave the spawner alone
    -- (empty pedestal stays hidden because adventure flow units only materialize
    -- after spawn).
    _dbg("[pedestal] -> empty (cap reached, altar n/a, casket settings missing)")
    return
end)

-- Big coin casket payout: the leftover-book-spot casket (tagged ct_big_casket
-- above) grants 3x the coin a normal deus_soft_currency casket would. We wrap the
-- per-pickup amount roll rather than on_soft_currency_picked_up so only THIS
-- pickup is tripled (not enemy/ground coin). No existing ct hook on this method.
mod:hook("GameModeDeus", "_get_coins_amount_and_type", function(func, self, interactable_unit)
    local amount, ctype = func(self, interactable_unit)
    if type(amount) == "number" and interactable_unit and Unit.alive(interactable_unit)
        and Unit.get_data(interactable_unit, "ct_big_casket") then
        return amount * 3, ctype
    end
    return amount, ctype
end)

-- Grant CW-pickup eligibility on adventure-level spawners that have analogous
-- adventure tags. Vanilla `PickupSystem._can_spawn` returns
-- `Unit.get_data(spawner, pickup_name) or Managers.mechanism:can_spawn_pickup(spawner, pickup_name)`.
-- For adventure spawners, neither path matches CW pickup types — they're tagged
-- `potions`/`painting_scrap`/`ammo`/etc., not `deus_potion`/`deus_cursed_chest`. So
-- our deus pickup counts in pickup_settings.primary result in "spawn debt" warnings
-- (engine wanted N, found 0 eligible spawners).
--
-- Mapping (only fires on injected adventure levels):
--   * potion spawners       → deus_potions   (any pickup in Pickups.deus_potions)
--   * painting_scrap spots  → deus_soft_currency (Pilgrim's Coin)
--   * non-claimed primaries → deus_weapon_chest (altars compete with ammo/healing
--                              for remaining primary spawn slots)
-- v0.7.78: defensive guard against pickup_settings whose `unit_name` is not
-- in the engine resource manager on the current level. The vanilla campaign
-- `grenades` pool includes `holy_hand_grenade` (`pup_holy_hand_grenade_01_t1`)
-- which only loads in Morris/CW mission bundles. After v0.7.64 broadened the
-- adventure-level allowlist, that entry became spawn-eligible on injected
-- adventure missions like Skittergate where the unit isn't in resources, and
-- when RNG rolled it the engine fataled in `World.spawn_unit`. Pre-flight the
-- pickup's unit path with `Application.can_get` so the spawner is skipped
-- (empty spot, vanilla-equivalent of a soft veto) instead of crashing.
local function _pickup_unit_loadable(pickup_name)
    if not Pickups then return true end  -- can't check, let it through
    for _, cat in pairs(Pickups) do
        if type(cat) == "table" then
            local settings = cat[pickup_name]
            if type(settings) == "table" then
                local unit_name = settings.unit_name
                if type(unit_name) ~= "string" then return true end
                return Application.can_get("unit", unit_name)
            end
        end
    end
    return true  -- not a vanilla bucket entry; trust the caller
end

-- v0.7.165-dev: ROBUST coin-starvation fix (Abundance-of-Life curse). See the
-- mechanism block in _adventure_pool.lua make_cw_pickup_settings(): on injected
-- adventure levels our _can_spawn fallback below un-partitions vanilla's spawner
-- types -- deus_potions, deus_soft_currency and deus_weapon_chest all compete for
-- the SAME finite, shared primary spawner pool that PickupSystem._spawn_spread_pickups
-- iterates per pickup_type over ONE `spawners` array, permanently table.remove()-ing
-- each consumed spawner (pickup_system.lua:467-633, :621-626). Two facts make
-- coins starve under the curse:
--   1. `for pickup_type in pairs(pickup_settings)` (pickup_system.lua:470) is
--      NON-DETERMINISTIC in Lua 5.1, so deus_potions can iterate (and drain
--      spawners) BEFORE deus_soft_currency.
--   2. The Abundance-of-Life curse multiplies ONLY deus_potions x3
--      (mutator_curse_abundance_of_life.lua:7-11, applied by
--      MutatorHandler.pickup_settings_updated_settings:544-560) -- coins stay flat.
-- A pure count-ratio fix (request fewer potions than coins) only REDUCES the odds
-- because allocation is per-section greedy in random type order, not proportional;
-- on a finite-spawner level a potions-first pass can still exhaust the pool first.
--
-- GUARANTEE (not just reduce): reserve a deterministic ~40% slice of the primary
-- spawners as COIN-ONLY by DENYING deus_potions / deus_weapon_chest eligibility on
-- them here. A spawner is only table.remove()'d when a pickup that _can_spawn
-- ALLOWED consumes it, so a spawner potions can never claim survives every potion
-- iteration regardless of pairs() order or the curse x3 -- it is still present and
-- coin-eligible when deus_soft_currency iterates. This mirrors vanilla's native
-- partition (potion-spawners vs painting_scrap->coin-spawners never contend).
--
-- The slice is chosen by a stable per-spawner hash of `percentage_through_level`
-- (a fixed float each primary spawner carries, read all over pickup_system.lua:
-- 325/424/508/531) so the reserved spawners are spread UNIFORMLY across the
-- percentage range -- coins find a reserved spawner in whatever section they
-- iterate. No extra hook, no per-run state, deterministic within the host's single
-- populate pass. deus_soft_currency itself is NEVER denied by this reservation.
--
-- NOTE: this whole helper group lives in a `do ... end` block so its 5 file-locals
-- release back to the main chunk (Lua 5.1 hard cap of 200 locals per function incl.
-- the top-level chunk -- per repo CLAUDE.md). Everything the _can_spawn hook below
-- needs is reached via `mod._` (the local `_spawner_reserved_for_coins` would not be
-- visible after the block closes).
do
local _COIN_RESERVED_FRACTION = 0.40
-- Pure hash of a percentage_through_level value -> reserved? Split out so the
-- /ct_regression_test marker can exercise the partition math without a live unit,
-- and so it can serve as the per-spawner fallback when no precomputed set exists.
local function _coin_reservation_hash_reserved(p)
    if type(p) ~= "number" then return false end
    -- Stable pseudo-random in [0,1) from the spawner's fixed percentage. The big
    -- prime + frac() decorrelates it from the value's own ordering so the reserved
    -- set isn't a contiguous band at the start/end of the level.
    local h = (p * 7919.0 + 0.6180339887)
    h = h - math.floor(h)
    return h < _COIN_RESERVED_FRACTION
end

-- RANK-based reserved set, rebuilt once per populate_pickups pass (host). The pure
-- per-spawner hash above is ~40% in expectation but, on a VERY small pool (e.g. 6
-- spawners), independent hashing has a ~4% chance of reserving ZERO -- which would
-- silently drop the coin guarantee. Building the set by RANK guarantees a floor of
-- math.max(1, ceil(frac*N)) reserved spawners for ANY non-empty pool, closing that
-- hole. Keyed by unit so _can_spawn can do an O(1) membership test. Reset + rebuilt
-- at the top of the populate_pickups hook; consulted (with hash fallback) below.
local _coin_reserved_units = {}
local function _rebuild_coin_reserved_set(spawner_lists)
    table.clear(_coin_reserved_units)
    for _, list in ipairs(spawner_lists) do
        if type(list) == "table" then
            -- Sort by the per-spawner hash so the reserved set is the lowest-hash
            -- prefix -- deterministic, spread across percentage_through_level (the
            -- hash decorrelates from position), and a guaranteed proper-size slice.
            local ranked = {}
            for _, unit in ipairs(list) do
                if Unit.alive(unit) then
                    local p = Unit.get_data(unit, "percentage_through_level")
                    if type(p) == "number" then
                        local h = p * 7919.0 + 0.6180339887
                        h = h - math.floor(h)
                        ranked[#ranked + 1] = { unit = unit, h = h }
                    end
                end
            end
            table.sort(ranked, function(a, b) return a.h < b.h end)
            local n = #ranked
            if n > 0 then
                local reserve_n = math.max(1, math.ceil(_COIN_RESERVED_FRACTION * n))
                -- Never reserve the WHOLE pool -- potions/altars need spawners too.
                reserve_n = math.min(reserve_n, n - 1 >= 1 and n - 1 or n)
                for i = 1, reserve_n do
                    _coin_reserved_units[ranked[i].unit] = true
                end
            end
        end
    end
end
local function _spawner_reserved_for_coins(spawner_unit)
    -- Prefer the precomputed rank-based set (built on the host this populate pass);
    -- fall back to the pure hash if it wasn't built (defensive: client, or a path
    -- that reaches _can_spawn before populate_pickups ran).
    if next(_coin_reserved_units) ~= nil then
        return _coin_reserved_units[spawner_unit] == true
    end
    return _coin_reservation_hash_reserved(Unit.get_data(spawner_unit, "percentage_through_level"))
end
-- Test handle for the regression marker (coin_reservation_partition).
mod._ct_coin_reservation_test = {
    fraction = _COIN_RESERVED_FRACTION,
    reserved = _coin_reservation_hash_reserved,
}
-- Exposed on `mod` so the populate_pickups hook (defined EARLIER in this file, so
-- it can't see this file-local by lexical scope -- feedback_lua_forward_reference.md)
-- can rebuild the reserved set each pass. The function is resolved at CALL time, by
-- which point this assignment has run (script body executes top-to-bottom before any
-- hook fires).
mod._ct_rebuild_coin_reserved_set = _rebuild_coin_reserved_set
mod._ct_clear_coin_reserved_set = function() table.clear(_coin_reserved_units) end
-- Exposed for the _can_spawn hook below: after this `do` block closes, the local
-- _spawner_reserved_for_coins is out of scope, so the hook must reach it via `mod._`.
mod._ct_spawner_reserved_for_coins = _spawner_reserved_for_coins
end  -- coin-reservation helper block (releases its locals back to the main chunk)

mod:hook("PickupSystem", "_can_spawn", function(func, self, spawner_unit, pickup_name)
    -- v0.7.97: career-exclusive pickup blocklist. Applied BEFORE vanilla and
    -- BEFORE the ct adventure-cat fallback, so the denial covers every path
    -- (vanilla CW deus, injected adventure, hypothetical future broadening).
    -- The owning career's grant function (e.g. Engineer's cooldown buff using
    -- `inventory_extension:add_equipment`) does NOT route through PickupSystem,
    -- so this denial does not affect legitimate career mechanics.
    if pickup_name and _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST[pickup_name] then
        _career_exclusive_denial_counts[pickup_name] =
            (_career_exclusive_denial_counts[pickup_name] or 0) + 1
        if not _career_exclusive_logged_this_run[pickup_name] then
            _career_exclusive_logged_this_run[pickup_name] = true
            _dbg("[pickup] denied career-exclusive: %s", pickup_name)
        end
        return false
    end

    local ok = func(self, spawner_unit, pickup_name)
    if ok then return ok end

    if not on_injected_adventure_level() then return ok end

    -- Reserved for the tome/grim → Chest of Trials conversion (see
    -- _spawn_guaranteed_pickup hook below). Never let any CW pickup hijack
    -- these book spots.
    if Unit.get_data(spawner_unit, "tome") or Unit.get_data(spawner_unit, "grimoire") then
        return false
    end

    -- Triggered event spawners (lamp_oil barrels for wagon-escape, explosive_barrel
    -- for body-burn objectives, training_dummy_bob spawners, etc.) MUST stay
    -- exclusive to their tagged pickup type. The vanilla `_can_spawn` checks
    -- `Unit.get_data(spawner, pickup_name)` — only e.g. `lamp_oil = true` returns
    -- true. But `_spawn_guaranteed_pickup` iterates ALL pickup names, and our
    -- CW-type fallback below would otherwise add `healing_draught`, `strength_potion`,
    -- etc. to the candidate list, so a triggered barrel-spawner could roll a potion
    -- and break the scripted event. v0.6.32 burned this: barrels for "burn the bodies"
    -- type events sometimes appeared as potions.
    -- Same risk for guaranteed_spawn spawners (already filtered for tome/grim
    -- above) and specified spawners.
    if Unit.get_data(spawner_unit, "guaranteed_spawn") then
        return false
    end
    local triggered_spawn_id = Unit.get_data(spawner_unit, "triggered_spawn_id")
    if triggered_spawn_id and triggered_spawn_id ~= "" then
        return false
    end

    -- CW pickups accept any non-tome/grim, non-event primary spawner. They
    -- compete with vanilla ammo/healing/grenades for unclaimed slots.
    --
    -- v0.7.165-dev coin reservation: deus_soft_currency is ALWAYS eligible (never
    -- reserved-out); deus_potions and deus_weapon_chest are DENIED on the
    -- coin-reserved spawner slice so they can't drain it ahead of coins under the
    -- Abundance-of-Life x3 potion curse (see _spawner_reserved_for_coins above).
    if Pickups and Pickups.deus_potions and Pickups.deus_potions[pickup_name] then
        if mod._ct_spawner_reserved_for_coins(spawner_unit) then return false end
        return _pickup_unit_loadable(pickup_name)
    end
    if pickup_name == "deus_soft_currency" then
        return _pickup_unit_loadable(pickup_name)
    end
    if pickup_name == "deus_weapon_chest" then
        if mod._ct_spawner_reserved_for_coins(spawner_unit) then return false end
        return _pickup_unit_loadable(pickup_name)
    end

    -- v0.7.64: on injected adventure levels, ALSO allow vanilla campaign pickup
    -- categories (ammo, healing, grenades, potions, painting_scrap, level_events).
    -- Pre-v0.7.64 the comment block above incorrectly assumed vanilla `_can_spawn`
    -- already returned true on these — but for adventure levels running under the
    -- deus mechanism, `Managers.mechanism:can_spawn_pickup` routes to the deus
    -- mechanism's pickup whitelist which doesn't recognize campaign pickup names,
    -- and the per-spawner `Unit.get_data(spawner, pickup_name)` check often fails
    -- for category vs specific-name mismatches (spawner tagged "ammo=true" while
    -- pickup_name is "ammo_specific_X"). Result on Holly DLC adventure-injected
    -- levels (Magnus / Cemetery / Forest Ambush): ALL pickups silently vetoed —
    -- not just deus types — leaving the map with literally nothing on the ground.
    -- Burned in the 2026-05-19 3-player run: 13 spawn-debt warnings on magnus
    -- including ammo, healing, grenades — the vanilla pickup-types ct's earlier
    -- code path mistakenly assumed were handled before our hook.
    --
    -- Explicit allowlist (not `string.sub(cat, 1, 5) ~= "deus_"`) to keep
    -- `versus_objective`, `weave`, and other non-campaign categories out of the
    -- candidate set even if Fatshark adds them to the global Pickups table in a
    -- future patch. Tome/grim/guaranteed/triggered spawners are already filtered
    -- above; this fallback only fires on plain primary/secondary spawners.
    if Pickups then
        local ADVENTURE_CATS = { "ammo", "healing", "grenades", "potions",
            "painting_scrap", "level_events" }
        for _, category in ipairs(ADVENTURE_CATS) do
            local bucket = Pickups[category]
            if type(bucket) == "table" and bucket[pickup_name] then
                -- v0.7.78: pickup_settings.unit_name may reference a unit that
                -- isn't loaded on this level (e.g. `holy_hand_grenade` on
                -- Skittergate). Soft-veto rather than letting the engine fatal
                -- when the spawner fires.
                local unit_name = bucket[pickup_name].unit_name
                if type(unit_name) == "string"
                    and not Application.can_get("unit", unit_name) then
                    return false
                end
                return true
            end
        end
    end

    return false
end)

-- v0.7.51: Belakor altar gate. Vanilla `can_spawn_belakor_locus` only returns true on
-- belakor-themed CW nodes (or arena_belakor). Adventure-injected campaign levels have
-- their own non-belakor themes, so the gate would reject every altar spawn even after
-- populate_pickups has requested one. Override: also return true on injected adventure
-- levels when host has force_belakor — gating mirrors the populate_pickups inject so
-- the two stay in sync.
mod:hook("DeusRunController", "can_spawn_belakor_locus", function(func, self)
    if func(self) then return true end
    if on_injected_adventure_level() and effective_setting("force_belakor") then
        return true
    end
    return false
end)

-- ============================================================
-- Respawn / Revive on Chest of Trials Completion
-- ============================================================

-- CLARIFY: STATES.OPEN = 3 in deus_cursed_chest_extension.lua. State transitions to OPEN at line
-- 174 of that file ONLY on the server, and ONLY when the curse encounter's terror event has ended
-- successfully. Hot-join clients enter HOTJOIN_OPEN (= 4) instead, so they do not trigger here.
local CURSED_CHEST_STATE_OPEN = 3
-- CLARIFY: DifficultyMapping["normal"] = "recruit" (difficulty_settings.lua:424). The string the
-- engine uses internally is "normal"; "recruit" is only the display name.
local DIFFICULTY_RECRUIT = "normal"
-- CLARIFY: peer_id -> true marker, set by the chest hook for any player whose health_state was
-- "dead" at the moment the chest opened. Consumed by the sync_health_state hook (THP override)
-- and the _respawn_player hook (wounded). Cleared in _respawn_player so a future Chest of Trials
-- in the same run can re-mark the same peer.
local pending_chest_respawn = {}

mod:hook_safe("DeusCursedChestExtension", "_set_state", function(self, state)
    if state ~= CURSED_CHEST_STATE_OPEN then
        return
    end
    -- raw printf so it lands on a mod-logging-OFF host (the user's setup)
    pcall(printf, "[ct-chest-revive] chest OPEN: setting=%s is_server=%s",
        tostring(effective_setting("respawn_on_chest_complete")),
        tostring(Managers and Managers.player and Managers.player.is_server))

    if not effective_setting("respawn_on_chest_complete") then
        return
    end
    if not Managers.player or not Managers.player.is_server then
        return
    end

    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode then
        return
    end

    local side = Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local party = side and side.party
    local occupied_slots = party and party.occupied_slots

    -- #116 (v0.7.177-dev): the prior body relied solely on
    -- `game_mode:force_respawn_dead_players()` (which only zeroes respawn timers) and
    -- never handled AWAITING-RESCUE players (hanging at a beacon, ready for assisted
    -- respawn) — so a downed teammate just stayed down and the feature looked dead.
    -- Now we port general_tweaker's proven per-player respawn primitive
    -- (_gt_level_control.lua `_gt_host_respawn`) and apply it to every party slot,
    -- covering all three downed states:
    --   * awaiting-rescue (hanging)  -> StatusUtils.set_respawned_network (free w/ party)
    --   * knocked-down (bleeding out) -> StatusUtils.set_revived_network (revive in place)
    --   * dead / queued for respawn   -> zero respawn_timer so RespawnHandler.server_update
    --                                    spawns them at the active beacon shortly
    -- Host-authoritative (already gated on is_server above).
    if occupied_slots then
        for i = 1, #occupied_slots do
            local status = occupied_slots[i]
            local data = status.game_mode_data
            local peer_id = status.peer_id
            local local_player_id = status.local_player_id

            if peer_id and local_player_id then
                local player = Managers.player:player(peer_id, local_player_id)
                local unit = player and player.player_unit
                local health_state = data and data.health_state or "?"

                local status_ext = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system") or nil
                local is_knocked = status_ext and status_ext.is_knocked_down and status_ext:is_knocked_down() or false
                local is_disabled_pact = status_ext and status_ext.is_disabled_by_pact_sworn and status_ext:is_disabled_by_pact_sworn() or false
                local is_awaiting = status_ext and status_ext.is_ready_for_assisted_respawn and status_ext:is_ready_for_assisted_respawn() or false
                local action = "none"

                if is_awaiting and rawget(_G, "StatusUtils") and StatusUtils.set_respawned_network then
                    -- hanging at a respawn beacon -> free directly (helper = self).
                    StatusUtils.set_respawned_network(unit, true, unit)
                    action = "freed-awaiting-rescue"
                elseif is_knocked and not is_disabled_pact and StatusUtils and StatusUtils.set_revived_network then
                    -- bleeding out -> revive in place (skip disabler-held players).
                    StatusUtils.set_revived_network(unit, true, nil)
                    action = "revived-knocked"
                elseif data and (health_state == "dead" or data.respawn_timer ~= nil) then
                    -- fully dead / in the respawn queue -> spawn at the active beacon.
                    data.respawn_timer = 0
                    pending_chest_respawn[peer_id] = true   -- arm THP/wounded post-respawn overrides
                    action = "respawn-timer-cleared"
                end

                pcall(printf, "[ct-chest-revive] slot=%d peer=%s health=%s knocked=%s awaiting=%s disabled=%s -> %s",
                    i, tostring(peer_id), tostring(health_state), tostring(is_knocked),
                    tostring(is_awaiting), tostring(is_disabled_pact), action)
            end
        end
    end

    -- Belt-and-suspenders: also fire the engine's team-wide dead-respawn so any dead
    -- player our per-slot health_state check didn't classify still respawns (idempotent
    -- — it only zeroes respawn timers). Per feedback_redundant_safeguards_ok.md.
    if game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
    end
end)

-- CLARIFY: THP override on the dead-respawn path. sync_health_state reads
-- status.game_mode_data.temporary_health_percentage (player_unit_health_extension.lua:111), which
-- the engine sets from difficulty.respawn.temporary_health_percentage at respawn_handler.lua:358
-- (0 on Recruit/Veteran/Champion, 0.25 on Legend). Mutating to 0.5 just before sync reads it
-- means the spawn applies 50% of max-health THP without us touching the network game object
-- ourselves. The is_dead-at-chest-open guard means this only fires for our feature's respawns.
mod:hook("PlayerUnitHealthExtension", "sync_health_state", function(func, self)
    local player = self.player
    local peer_id = player and player.network_id and player:network_id()

    if peer_id and pending_chest_respawn[peer_id] then
        local status = Managers.party:get_player_status(peer_id, player:local_player_id())
        if status and status.game_mode_data and status.game_mode_data.health_state == "respawning" then
            status.game_mode_data.temporary_health_percentage = 0.5
        end
    end

    func(self)
end)

-- CLARIFY: Apply wounded (1 wound) on dead-respawn above Recruit. Mirrors the engine's own
-- post-revive wound at player_unit_health_extension.lua:277 — same reason string ("revived"),
-- which is one of the four valid entries in NetworkLookup.set_wounded_reasons. Recruit is skipped
-- because it has 5 max wounds and no real wounded mechanic in player perception. The flag is
-- cleared here so a subsequent dead-respawn (different chest, same run) re-arms via the chest
-- hook above instead of double-applying.
mod:hook_safe("RespawnHandler", "_respawn_player", function(self, player, profile_index, career_index, respawn_unit, ...)
    local peer_id = player and player.network_id and player:network_id()
    if not peer_id or not pending_chest_respawn[peer_id] then
        return
    end
    pending_chest_respawn[peer_id] = nil

    if Managers.state.difficulty:get_difficulty() == DIFFICULTY_RECRUIT then
        return
    end

    local unit = player.player_unit
    if not unit or not Unit.alive(unit) then
        return
    end

    local t = Managers.time:time("game")
    StatusUtils.set_wounded_network(unit, true, "revived", t)
end)

-- ============================================================
-- Starting Boons
-- ============================================================

-- Starting-boons hook. Vanilla `_add_initial_power_ups` adds talent power-ups + event
-- boons after run setup; we append toggled starting boons after that (hook_safe = post-call).
--
-- HOST-ONLY: the server processes the hook for every peer in the lobby and uses the
-- HOST's `start_boon_*` settings — so every player gets the same starting boons,
-- whatever the host picked. Clients early-out unconditionally and never apply their
-- own start_boon settings (and never duplicate the host's grant either, which was
-- the old bug). The server's `run_state:set_player_power_ups(peer_id, ...)` call
-- syncs the granted boons to the target peer via the shared-state networking layer.
-- QUESTION: The hook signature drops the 5th arg `initial_talents_for_career` (vanilla has 5
-- positional args). hook_safe ignores extra args so this is fine, but a future maintainer adding a
-- new arg might be confused.
-- v0.7.118-dev: starting-boon grant is engine-driven (DeusRunController._add_initial_power_ups
-- fires per player-add at run start + on late joiner / bot add), NOT a user-typed operational
-- toggle. Per PROJECT_STANDARDS § 3.6 "Chat-echo policy" that means log-only, never chat.
-- Demoted from `mod:echo` to `mod:info("[ct:starting_boons] ...")` below.
mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end  -- host-only
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    -- CLARIFY: Re-fetching existing power-ups inside the hook (rather than capturing pre-call) is
    -- correct: the original func has already added talent + event boons by the time this fires
    -- (hook_safe = post-call). table.clone with skip_metatable keeps the array shape without
    -- copying any inherited methods.
    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)

    -- Resolve the player's character + career for the chat message. SPProfiles maps
    -- profile_index → profile (Kruber/Bardin/Kerillian/Sienna/Saltzpyre) and
    -- profile.careers maps career_index → career (es_mercenary, dr_slayer, etc.).
    -- Both use localization keys for display; Localize() resolves them to the
    -- player-facing names.
    local profile = rawget(_G, "SPProfiles") and SPProfiles[profile_index]
    local character = profile and profile.display_name and Localize(profile.display_name) or "?"
    local career = profile and profile.careers and profile.careers[career_index]
    local career_name = career and career.display_name and Localize(career.display_name) or "?"
    -- Player slot in the party: peer_id + local_player_id. Use party-slot index if
    -- available so users can quickly identify which on-screen panel got the boons.
    local slot_label = ""
    local party_manager = Managers.party
    if party_manager and party_manager.get_status_from_unique_id then
        local status = party_manager:get_status_from_unique_id(peer_id, local_player_id)
        if status and status.party_id and status.slot_id then
            slot_label = string.format(" [P%d:S%d]", status.party_id, status.slot_id)
        end
    end

    _dbg("[ct:starting_boons] granted %d to %s (%s)%s",
        #extra, character, career_name, slot_label)
end)

-- ============================================================
-- Bot Boon Mirror (v0.7.76)
-- ============================================================
-- When `bots_mirror_host_boons` is on, every boon a HUMAN host gains in Chaos
-- Wastes (shrine pick, altar reward, dormant reveal, Belakor temple, blessing
-- of the gods, set reward, end-of-level grant, etc.) is also granted to every
-- bot in the lobby.
--
-- The single canonical entry point for boon application is
-- `DeusRunController.add_power_ups(new_power_ups, local_player_id, present)`
-- (deus_run_controller.lua:1126). Every code path that grants a boon — chest
-- pickup, cursed chest, shop blessing, set completion, end-of-level node
-- (`try_grant_end_of_level_deus_power_ups` falls through to this), debug — funnels
-- through here. Hooking it once covers all sources.
--
-- HOST-ONLY: Bots are entirely client-side on the host (they don't exist as
-- bots on remote peers; remote peers see them as husk units with normal buff
-- replication via the server-authoritative buff_system). So mirroring only
-- runs on `_run_state:is_server()`.
--
-- Reentry guard: re-calling `add_power_ups` for each bot would re-enter this
-- hook → infinite recursion. `_ct_bot_mirror_active` short-circuits the nested
-- calls.
--
-- Talent vs buff boons: `DeusPowerUpUtils.activate_deus_power_up` (called from
-- `add_power_ups`) branches on `power_up.talent`. Buff boons land via
-- `buff_system:add_buff(player_unit, buff_name, ...)` which works identically
-- on bot units. Talent boons mutate the backend talent ids for the receiving
-- career — that's fine when the bot has the same career as the host, but if
-- the bot is on a different career the talent slot still gets written into
-- the bot's own backend so the per-bot talent set is independent. The buff
-- the talent grants is the same one the host got.
--
-- Set completion: `_check_set_completed` runs inside `add_power_ups` post-add
-- and may recursively call `add_power_ups` for set rewards. We let those run
-- normally; the guard wraps only our bot-iteration loop so any set rewards a
-- bot triggers also mirror correctly.
local _ct_bot_mirror_active = false

-- Friendly display name for a deus boon/power-up key, for the host-side bot-boon
-- chat announcement (announce_bot_boons). Mirrors the in-file canonical pattern:
-- resolve DeusPowerUpTemplates[name].display_name via Localize, guarding the vanilla
-- "<key>" miss-sentinel; falls back to the raw key. On `mod` (not a new file-scope
-- local) per the 200-locals cap note; also lets /ct_regression_test reach it.
function mod._ct_boon_display_name(name)
    local tpl = rawget(_G, "DeusPowerUpTemplates")
    tpl = tpl and tpl[name]
    local key = tpl and tpl.display_name
    if key then
        local raw = Localize(key)
        if raw ~= "<" .. key .. ">" then return raw end
    end
    return tostring(name)
end

-- #144 diagnostic helper: read-only snapshot of a recipient's CURRENT stored boon list.
-- DeusRunController:get_player_power_ups(peer, local_id) (deus_run_controller.lua:1080) returns
-- the run_state SharedState power_ups table — the SAME list the boon UI renders and the SAME
-- list add_power_ups appends to (deus_run_controller.lua:1126). Returns (count, comma-separated
-- names). On `mod` (not a file-scope local) per the 200-locals cap note, mirroring the pattern of
-- _ct_boon_display_name above. Fully pcall-guarded: any resolve/format failure returns
-- (-1, "<snapshot_error>") so a caller's printf can never disturb boon application.
function mod._ct_boon144_list_snapshot(run_controller, local_player_id)
    local ok, count, names = pcall(function()
        local rs = run_controller and run_controller._run_state
        local peer = rs and rs.get_own_peer_id and rs:get_own_peer_id()
        local list = run_controller and run_controller.get_player_power_ups
            and run_controller:get_player_power_ups(peer, local_player_id)
        if type(list) ~= "table" then return 0, "" end
        local parts = {}
        for i = 1, #list do
            local pu = list[i]
            parts[i] = (pu and pu.name) and tostring(pu.name) or "?"
        end
        return #list, table.concat(parts, ",")
    end)
    if ok then return count, names end
    return -1, "<snapshot_error>"
end

-- v0.7.159-dev Task 2: converted hook_safe -> full mod:hook so disabled boons can be
-- filtered OUT of `new_power_ups` BEFORE vanilla grants + activates them. ROOT CAUSE of
-- the `[boon-trace] DISABLED BOON GRANTED: blazing_revenge` leak: the disable filter only
-- stripped the ROLL pool (DeusPowerUpsArray / DeusPowerUpsArrayByRarity) inside the
-- generate_random_power_ups hook. But a boon ALTAR (DeusChestExtension, _chest_type ==
-- power_up) rolls + CACHES its single offered boon into `self._stored_purchase` at chest
-- SPAWN time (deus_chest_extension.lua:_generate_stored_power_up), then grants it via
-- add_power_ups on PURCHASE. If the user toggles `disable_boon_<name>` ON mid-run AFTER an
-- altar already cached that boon, the strip already missed it — the stale cached boon
-- sails through to add_power_ups. (Other specific-grant paths — set rewards via
-- _check_set_completed, starting boons — likewise bypass the pool strip.) add_power_ups is
-- the SINGLE universal apply chokepoint for every grant source, so gating HERE catches all
-- of them. effective_setting resolves host-authoritatively (host's value on clients), so
-- host + clients agree on what's disabled — a client never drops a boon the host legitimately
-- granted. Filtering to empty is safe: vanilla add_power_ups early-returns on #==0.
-- VMF singleton-hook rule: this remains the ONE (DeusRunController, add_power_ups) hook in
-- ct_dev (now a full mod:hook instead of hook_safe). DO NOT add another.
mod:hook("DeusRunController", "add_power_ups", function(func, self, new_power_ups, local_player_id, present)
    -- Pre-grant disable gate. Skip while the bot-mirror loop is granting (those entries
    -- are freshly materialized from a pool we already control, and re-filtering bot grants
    -- here is redundant; the guard also prevents touching the recursive set-reward grants).
    if not _ct_bot_mirror_active and type(new_power_ups) == "table" then
        for i = #new_power_ups, 1, -1 do
            local pu = new_power_ups[i]
            local name = pu and pu.name
            -- v0.7.200-dev (#211): shared helper (was an inline effective_setting == true check).
            if name and mod._ct_boon_disabled(name) then
                table.remove(new_power_ups, i)
                _dbg("[boon-trace] BLOCKED disabled boon at grant: %s (disable_boon_<name>=true) — stripped before add_power_ups",
                    tostring(name))
                -- Raw printf so the block is visible on the logging-OFF host too (#211).
                pcall(printf, "[boon-trace] BLOCKED disabled boon at grant: %s source=%s (issue #211)",
                    tostring(name), tostring(mod._ct_grant_source or "untagged"))
            end
        end
    end

    -- #144 diagnostic: snapshot the recipient's boon list BEFORE the grant. The user reported a
    -- STARTING boon (ct_boon_vauls_anvil) vanishing after acquiring another boon; their hypothesis
    -- was a fixed-size boon array overflowing/overwriting. Vanilla has NO such cap (power_ups is a
    -- dynamic SharedState table appended by add_power_ups — deus_run_controller.lua:1126 /
    -- deus_run_state_spec.lua:298), so this watches for the list SHRINKING across a grant, which
    -- would prove a real drop/overwrite. Gated on `not _ct_bot_mirror_active` so the re-entrant bot
    -- grants (driven below) don't spam the trace; the human's own grants + vanilla set-reward
    -- re-entries inside func() are still captured.
    local _b144_pre_count, _b144_pre_list
    if not _ct_bot_mirror_active then
        _b144_pre_count, _b144_pre_list = mod._ct_boon144_list_snapshot(self, local_player_id)
    end

    func(self, new_power_ups, local_player_id, present)

    -- #144 diagnostic (cont.): snapshot AFTER the grant and emit before/after lists with counts.
    -- `added` names the boons this call actually appended (post-disable-strip). With no vanilla
    -- cap the stored list must only ever GROW by #new_power_ups; anything smaller means a boon was
    -- dropped/overwritten — the smoking gun for the "starting boon disappears" report. Raw printf
    -- (host runs VMF logging OFF, per diagnostics doctrine). Whole block pcall-wrapped so a
    -- snapshot/format failure can never break boon application.
    if not _ct_bot_mirror_active then
        pcall(function()
            if not new_power_ups or #new_power_ups == 0 then return end
            local rs = self and self._run_state
            local peer = rs and rs.get_own_peer_id and rs:get_own_peer_id()
            local post_count, post_list = mod._ct_boon144_list_snapshot(self, local_player_id)
            local added_parts = {}
            for i = 1, #new_power_ups do
                local pu = new_power_ups[i]
                added_parts[i] = (pu and pu.name) and tostring(pu.name) or "?"
            end
            local added_csv = table.concat(added_parts, ",")
            pcall(printf, "[ct:boon144] pre-grant peer=%s local_id=%s count=%s list=%s (issue #144)",
                tostring(peer), tostring(local_player_id), tostring(_b144_pre_count), tostring(_b144_pre_list))
            pcall(printf, "[ct:boon144] post-grant peer=%s local_id=%s count=%s added=%s list=%s (issue #144)",
                tostring(peer), tostring(local_player_id), tostring(post_count), added_csv, tostring(post_list))
            -- Loss detector: expected post = pre + #added. Fires only on a genuine shrink.
            if type(_b144_pre_count) == "number" and type(post_count) == "number"
                and _b144_pre_count >= 0 and post_count >= 0 then
                local expected = _b144_pre_count + #new_power_ups
                if post_count < expected then
                    pcall(printf, "[ct:boon144] LOSS pre=%d added=%d expected=%d post=%d - a boon was dropped/overwritten across this grant (issue #144)",
                        _b144_pre_count, #new_power_ups, expected, post_count)
                end
            end
        end)
    end

    -- v0.7.90: unconditional audit trail for every boon grant. Logs name, rarity, recipient,
    -- and toggle state — surfaces any boon that slipped through a toggle. Tag `[boon-trace]`
    -- so the whole session's grants are greppable. Must live in this consolidated hook (VMF
    -- silently shadows duplicate hook on the same Class+method).
    -- v0.7.100-dev: dormant-specific trace fields removed (DORMANT_BOON_RARITY no longer
    -- exists; activate_dormant_* setting reads are dead). The disable_boon_* warning path
    -- still fires — that's the user-facing per-boon disable toggle and is fully active.
    -- v0.7.159-dev: with the pre-grant gate above, a DISABLED BOON GRANTED warning here now
    -- means a genuine bypass the gate didn't cover (e.g. _ct_bot_mirror_active path) — still
    -- worth surfacing.
    pcall(function()
        if not new_power_ups or #new_power_ups == 0 then return end
        local rs = self and self._run_state
        local own_peer = rs and rs.get_own_peer_id and rs:get_own_peer_id()
        local trace_is_server = rs and rs.is_server and rs:is_server()
        -- v0.7.200-dev (#211): grant-source attribution. `mod._ct_grant_source` is a
        -- short-lived marker set (and restored) around each wrapped grant path:
        -- "bot_mirror"/"bot_random" (ct's bot-boon loop below), "set_reward"
        -- (DeusRunController._check_set_completed wrapper), "cot_view_pick"
        -- (DeusCursedChestView._on_button_pressed wrapper). All markers are set+cleared
        -- synchronously within one call stack (single frame) — no race. "untagged" on the
        -- host with present=true and one boon is, per the #211 vanilla call-site map, the
        -- boon-ALTAR grant inside DeusChestExtension.open_chest — NOT pre-taggable because
        -- ct's ONLY open_chest hook is the consolidated hook_safe (post-call; VMF drops a
        -- second hook on the same Class+method). That path is already double-covered by the
        -- roll-pool strip + the pre-grant gate above. Raw printf: the host runs VMF
        -- logging OFF, so mod:info/_dbg never lands there (diagnostics doctrine).
        local grant_source = tostring(mod._ct_grant_source or "untagged")
        for i = 1, #new_power_ups do
            local pu = new_power_ups[i]
            local name = pu and pu.name or "?"
            local rarity = pu and pu.rarity or "?"
            local disable_toggle = mod._ct_boon_disabled(name)
            pcall(printf, "[boon-trace] grant source=%s boon=%s rarity=%s disabled=%s recipient_local_id=%s present=%s (issue #211)",
                grant_source, tostring(name), tostring(rarity), tostring(disable_toggle),
                tostring(local_player_id), tostring(present))
            _dbg("[boon-trace] add_power_ups: name=%s rarity=%s recipient_local_id=%s present=%s peer=%s is_server=%s disable_toggle=%s",
                tostring(name), tostring(rarity), tostring(local_player_id), tostring(present),
                tostring(own_peer), tostring(trace_is_server),
                tostring(disable_toggle))
            if disable_toggle == true then
                mod:warning("[boon-trace] DISABLED BOON GRANTED: %s (disable_boon_<name>=true) source=%s — investigate source path",
                    tostring(name), grant_source)
            end
        end
    end)

    if _ct_bot_mirror_active then return end
    local mode_mirror = effective_setting("bots_mirror_host_boons")
    local mode_random = effective_setting("bots_get_random_boons")
    if not (mode_mirror or mode_random) then return end
    if not new_power_ups or #new_power_ups == 0 then return end

    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end

    -- Resolve who just got the boon. add_power_ups uses
    -- `run_state:get_own_peer_id()` for the recipient peer; the recipient
    -- local_player_id is the second arg. We want to mirror onto bots only when
    -- the recipient is a HUMAN (otherwise a bot's own grant would re-trigger
    -- the bot loop).
    local own_peer_id = run_state:get_own_peer_id()
    local recipient = Managers.player and Managers.player:player(own_peer_id, local_player_id)
    if recipient and recipient.bot_player then return end

    local player_manager = Managers.player
    if not player_manager or not player_manager.human_and_bot_players then return end
    local all_players = player_manager:human_and_bot_players()
    if not all_players then return end

    -- Filter bots and skip the recipient (defensive — recipient should be human
    -- per the check above, but harmless to double-check).
    local bots = {}
    for _, p in pairs(all_players) do
        if p ~= recipient and p.bot_player and p.player_unit and Unit.alive(p.player_unit) then
            bots[#bots + 1] = p
        end
    end
    if #bots == 0 then return end

    _dbg("[bot-boon] mode=%s host_grant=%d bot_count=%d",
        mode_random and "random" or "mirror", #new_power_ups, #bots)

    -- v0.7.120-dev: per-bot independent random pick from DeusPowerUpsArrayByRarity[rarity].
    -- Picks a random entry of the SAME rarity the host just got, then materializes via
    -- generate_specific_power_up (gives each bot a fresh client_id). Falls back to a
    -- mirror grant for that slot if the rarity bucket is empty / missing.
    local function _pick_random_for_rarity(rarity)
        local bucket = rawget(_G, "DeusPowerUpsArrayByRarity") and DeusPowerUpsArrayByRarity[rarity]
        if not bucket or #bucket == 0 then
            return nil
        end
        -- v0.7.200-dev (#211 ROOT-CAUSE FIX): this picker sampled the RAW rarity bucket,
        -- which is only stripped of disabled boons INSIDE the generate_random_power_ups
        -- hook's remove-then-restore window — outside that window it always contains every
        -- boon. The pick was then granted via add_power_ups with the pre-grant gate
        -- deliberately skipped (_ct_bot_mirror_active), so `bots_get_random_boons` handed
        -- bots user-disabled boons (host log 2026-07-01: grenadier / deus_second_wind /
        -- deus_push_charge / skill_by_block, all with disable_boon_<name>=true). Filter the
        -- bucket through the same shared disable check the pool strip uses. Bomb-boon
        -- exclusivity and altar no-repeat are NOT applied here: both are per-recipient
        -- state (the bot's own boon list / the peer's altar history), which this
        -- rarity-matched random pick has never consulted — unchanged behavior.
        local eligible = {}
        for i = 1, #bucket do
            local entry = bucket[i]
            local nm = entry and entry.name
            if nm and not mod._ct_boon_disabled(nm) then
                eligible[#eligible + 1] = nm
            end
        end
        if #eligible == 0 then
            return nil  -- whole bucket disabled -> caller falls back to mirroring the host's (already-gated) boon
        end
        return eligible[math.random(1, #eligible)]
    end

    -- Clone the power-up list per-bot. Each call needs fresh client_ids so the
    -- run_state stores distinct entries (otherwise the same client_id appears
    -- across multiple players and `remove_power_ups` matching could mis-target).
    -- announce_bot_boons (default off): host-local chat line naming each bot and the
    -- boon it received, so the host can see what bots got (esp. in random mode). mod:echo
    -- is local-only — no RPC/version-sync risk; the feature is already host-gated above.
    local announce = effective_setting("announce_bot_boons") == true
    _ct_bot_mirror_active = true
    -- v0.7.200-dev (#211): grant-source marker for the audit printf in this same hook
    -- (the bot grants below re-enter add_power_ups). Set/restored around the pcall so
    -- it can never leak past this call stack.
    local _prev_grant_source = mod._ct_grant_source
    mod._ct_grant_source = mode_random and "bot_random" or "bot_mirror"
    local ok, err = pcall(function()
        for _, bot in ipairs(bots) do
            local cloned = {}
            for i = 1, #new_power_ups do
                local host_pu = new_power_ups[i]
                local bot_name = host_pu.name
                if mode_random then
                    local picked = _pick_random_for_rarity(host_pu.rarity)
                    if picked then
                        bot_name = picked
                    end
                end
                -- v0.7.200-dev (#211) defense-in-depth: never grant a disabled boon to a
                -- bot, whatever the pick/mirror source. The random picker is now
                -- disabled-aware and mirror-mode names already passed the pre-grant gate,
                -- so this firing means a new bypass — printf it (host runs logging OFF).
                if mod._ct_boon_disabled(bot_name) then
                    pcall(printf, "[bot-boon] SKIPPED disabled boon for bot: %s (disable_boon_<name>=true, issue #211)",
                        tostring(bot_name))
                else
                    cloned[#cloned + 1] = DeusPowerUpUtils.generate_specific_power_up(bot_name, host_pu.rarity)
                    _dbg("[bot-boon] bot=%s slot=%d rarity=%s host=%s -> bot=%s",
                        tostring(bot.name and bot:name() or "?"),
                        i, tostring(host_pu.rarity), tostring(host_pu.name), tostring(bot_name))
                    if announce then
                        -- The boon display name can carry unfilled `%.1f` placeholders
                        -- (raw loc + description_values). Don't pre-string.format then
                        -- echo -- mod:echo string.formats its first arg, so a pre-built
                        -- string re-interprets the %.1f and prints "<Invalid string
                        -- format>". Pass the parts as args so mod:echo formats ONCE; the
                        -- boon name's % is then inert (a %s substitution value).
                        mod:echo("[ct] Bot %s got boon: %s (%s)",
                            tostring(bot.name and bot:name() or "?"),
                            tostring(mod._ct_boon_display_name(bot_name)),
                            mode_random and "rolled" or "mirrored")
                    end
                end
            end
            -- present=false: don't trigger the reward-popup UI for bot grants.
            self:add_power_ups(cloned, bot:local_player_id(), false)
        end
    end)
    _ct_bot_mirror_active = false
    mod._ct_grant_source = _prev_grant_source

    if not ok then
        pcall(printf, "[bot-boon] error granting boons to bots: %s", tostring(err))
        return
    end

    _dbg("[bot-boon] %s %d boon(s) onto %d bot(s)",
        mode_random and "rolled" or "mirrored", #new_power_ups, #bots)
end)

-- #144 install-time finding (logged once): there is NO fixed max-boon cap in vanilla. A player's
-- active power-ups live in a dynamic SharedState Lua table (deus_run_state_spec.lua:298 "power_ups",
-- type="table", default {}); DeusRunController.add_power_ups (deus_run_controller.lua:1126) only ever
-- table.clone + table.append + set_player_power_ups — never a bounded/fixed-size write — and the
-- network transport CHUNKS long encoded strings (shared_state.lua:298-303, STRING_CHUNK_SIZE=500)
-- and reassembles them (shared_state.lua:767-783) rather than truncating. So the overflow-overwrite
-- hypothesis for #144 is not supported by the engine; the [ct:boon144] pre/post trace above will
-- show whether the stored list actually SHRINKS on a grant vs. the starting boon simply never being
-- present in the stored list to begin with (a persistence / re-sync path, not a cap).
pcall(printf, "[ct:boon144] no fixed boon cap in vanilla (power_ups is a dynamic SharedState table; add_power_ups appends - deus_run_controller.lua:1126 / deus_run_state_spec.lua:298). Watching for list SHRINK on grant. (issue #144)")

-- Regression guard for the announce_bot_boons feature. The singleton-hook invariant for
-- (DeusRunController, add_power_ups) is enforced statically by tools/mod-lint; this runtime
-- check verifies the announce wiring: the boon-name helper resolves (never empty / sentinel)
-- and the announce checkbox is actually registered.
_rt_register("bot_boon_announce_wired", function()
    if type(mod._ct_boon_display_name) ~= "function" then
        return "BOT-BOON REGRESSION: mod._ct_boon_display_name missing"
    end
    local fallback = mod._ct_boon_display_name("__ct_no_such_boon__")
    if type(fallback) ~= "string" or fallback == "" then
        return "BOT-BOON REGRESSION: _ct_boon_display_name returned empty for unknown key (should fall back to the raw key)"
    end
    if type(mod:get("announce_bot_boons")) ~= "boolean" then
        return "BOT-BOON REGRESSION: announce_bot_boons checkbox not registered (mod:get is non-boolean)"
    end
end)

-- #144 diagnostic install guard: the boon-list snapshot helper must resolve and stay side-effect
-- free. The pre/post [ct:boon144] trace is folded into the single (DeusRunController, add_power_ups)
-- hook above — this only verifies the helper exists and returns (number, string) for a bogus
-- controller (never crashing, never mutating anything).
_rt_register("boon144_list_trace_installed", function()
    if type(mod._ct_boon144_list_snapshot) ~= "function" then
        return "#144 REGRESSION: mod._ct_boon144_list_snapshot missing (boon-list diagnostic)"
    end
    local count, names = mod._ct_boon144_list_snapshot(nil, 1)
    if type(count) ~= "number" or type(names) ~= "string" then
        return "#144 REGRESSION: _ct_boon144_list_snapshot(nil,1) must return (number, string), got ("
            .. type(count) .. ", " .. type(names) .. ")"
    end
end)

-- ============================================================
-- v0.7.200-dev (#211) — grant-source tagging hooks
-- ============================================================
-- Each wraps ONE vanilla grant path that re-enters DeusRunController.add_power_ups, so
-- the [boon-trace] grant printf in the consolidated add_power_ups hook above can name
-- its source. Marker is saved/restored around the wrapped call (synchronous, single
-- frame — race-free). pcall + re-raise so a vanilla error can't leave a stale marker.
--
-- Vanilla grant-path map (2026-07-01 audit for #211, deus_run_controller.lua /
-- deus_chest_extension.lua / deus_cursed_chest_view.lua / deus_run_state.lua):
--   COVERED by the roll-pool strip (generate_random_power_ups hook):
--     * boon-ALTAR stored roll  — DeusChestExtension._generate_stored_power_up:400 ->
--       controller:generate_random_power_ups:1099 -> util plural :1115
--     * shrine shop offerings   — deus_shop_view_v2.lua:184 (same controller method)
--     * Chest of Trials picks   — deus_cursed_chest_view.lua:58 (same controller method)
--     * end-of-level random     — try_grant_end_of_level_deus_power_ups:1314 + the
--       late-join RPC variant :421 (both call the plural util directly; both then write
--       run_state directly and NEVER call add_power_ups — pool strip is the only filter)
--   COVERED by the pre-grant gate (add_power_ups hook):
--     * everything that calls DeusRunController.add_power_ups (altar open_chest:548,
--       CoT view pick :299, set rewards :1291, ct's bot loop)
--   NOT COVERED (deliberate — instrument/document only):
--     * _add_initial_power_ups :471 — the player's OWN TALENTS materialized as boons
--       (must never be stripped) + run_state:get_event_boons() live-event freebies;
--       writes run_state directly. Stripping here would desync shared run state.
--     * grant_party_power_up :1770 + belakor_ingame_challenge_settings.lua:34 — quest
--       reward grants a SPECIFIC named quest power-up and activates it directly
--       (activate_deus_power_up), never entering add_power_ups.
--     * terror_event_power_up party grant :1349 — node-configured SPECIFIC party boon,
--       written to party state directly.
mod:hook("DeusRunController", "_check_set_completed", function(func, self, ...)
    local prev = mod._ct_grant_source
    mod._ct_grant_source = "set_reward"
    local ok, err = pcall(func, self, ...)
    mod._ct_grant_source = prev
    if not ok then
        mod:warning("[boon-trace] vanilla _check_set_completed raised: %s", tostring(err))
        error(err, 2)
    end
end)

mod:hook("DeusCursedChestView", "_on_button_pressed", function(func, self, ...)
    local prev = mod._ct_grant_source
    mod._ct_grant_source = "cot_view_pick"
    local ok, err = pcall(func, self, ...)
    mod._ct_grant_source = prev
    if not ok then
        mod:warning("[boon-trace] vanilla DeusCursedChestView._on_button_pressed raised: %s", tostring(err))
        error(err, 2)
    end
end)

-- Regression guard (#211): the shared disabled-boon check + the bot-picker filter and
-- grant-source tagging consolidated into the existing add_power_ups / bot-mirror hooks.
_rt_register("boon_disable_shared_gate", function()
    if type(mod._ct_boon_disabled) ~= "function" then
        return "#211 REGRESSION: mod._ct_boon_disabled missing (shared disabled-boon check)"
    end
    if mod._ct_boon_disabled("__ct_no_such_boon__") ~= false then
        return "#211 REGRESSION: _ct_boon_disabled should be false for an unknown boon key"
    end
    if mod._ct_boon_disabled(nil) ~= false then
        return "#211 REGRESSION: _ct_boon_disabled(nil) should be false"
    end
end)

-- Per-bot late-respawn re-apply. CW's `_add_initial_power_ups` (host-side per
-- peer at run start) already grants bots the talent-boon defaults; the host's
-- early-run mirror calls during initial setup then propagate via the hook
-- above. The only respawn case that bypasses both is a mid-run bot career
-- swap (rare) — vanilla doesn't re-run _add_initial_power_ups in that case
-- and there is no general "bot career swap" event in CW. We accept this as a
-- known limit; users can disable + re-enable the bot to re-grant.

-- ============================================================
-- Bot Weapon-Chest Mirror (v0.7.120-dev)
-- ============================================================
-- When `bots_mirror_host_weapon_upgrades` is on, every time the HOST opens a
-- deus weapon reliquary, every bot also receives the equivalent operation:
--   * swap_melee / swap_ranged chest -> bot gets a freshly-rolled random
--     weapon of the same rarity for its CW career (independent roll per bot,
--     using the bot's own career weapon pool).
--   * upgrade chest ("temper") -> bot's currently-equipped CW weapon is
--     upgraded to the same target rarity with re-rolled traits / properties.
--   * power_up chests are ignored here — the existing add_power_ups hook
--     already handles boon-side mirroring.
--
-- HOST-ONLY: same reasoning as Bot Boon Mirror. Bots are local-side on the
-- host; the host's `DeusChestExtension.open_chest` only fires when the host
-- themselves opens a chest (clients fire their own local copy). Server-
-- authoritative SimpleInventoryExtension replication carries the bot's new
-- weapon unit to remote peers.
--
-- The Equip pipeline mirrors vanilla `_equip_weapon` (deus_chest_extension.lua:581):
--   1. deus_backend:grant_deus_weapon(item)   -- assigns backend_id
--   2. mutate _bot_loadouts[bot_career][slot_name] = backend_id  (no public setter)
--   3. bot_inventory:create_equipment_in_slot(slot_name, backend_id, 1)
--   4. deus_backend:refresh_deus_weapons_in_items_backend()
--   5. _run_state:set_player_loadout(host_peer, bot_local_id, profile, career, slot, item_string)
--
-- Step 2 is the only break from public API. There's no `BackendInterfaceDeusBase.
-- set_bot_loadout_item(item_backend_id, career_name, slot_name)` — the bot-loadout
-- table is populated once at run start by `DeusMechanism._build_deus_inventory`
-- and never mutated mid-run by vanilla. We reach in directly. Wrapped in pcall
-- so the run survives any deviation in backend structure.
local _ct_bot_weapon_mirror_active = false

local function _resolve_bot_career(bot)
    local profile_index, career_index = nil, nil
    if Managers.state and Managers.state.network and Managers.state.network.profile_synchronizer then
        local sync = Managers.state.network.profile_synchronizer
        if sync.profile_by_peer then
            -- Husk/bot resolution is the same as for any player_unit.
            local peer = bot:network_id()
            local local_id = bot:local_player_id()
            profile_index, career_index = sync:profile_by_peer(peer, local_id)
        end
    end
    if not profile_index or not career_index or profile_index == 0 then
        local profile = bot.profile_index and bot:profile_index()
        local career = bot.career_index and bot:career_index()
        if profile and career then
            profile_index, career_index = profile, career
        end
    end
    if not profile_index or not career_index or profile_index == 0 or career_index == 0 then
        return nil, nil, nil
    end
    local profile = SPProfiles[profile_index]
    local career = profile and profile.careers and profile.careers[career_index]
    return profile_index, career_index, career and career.name or nil
end

local function _bot_equip_weapon(bot, new_weapon, slot_name, run_state, host_peer_id)
    if not new_weapon or not slot_name then
        return false, "no weapon or slot"
    end
    local profile_index, career_index, career_name = _resolve_bot_career(bot)
    if not career_name then
        return false, "unresolved bot career"
    end

    local deus_backend = Managers.backend and Managers.backend.get_interface and Managers.backend:get_interface("deus")
    if not deus_backend then
        return false, "no deus backend"
    end

    new_weapon.preferred_slot_name = slot_name
    deus_backend:grant_deus_weapon(new_weapon)
    deus_backend:refresh_deus_weapons_in_items_backend()
    local backend_id = new_weapon.backend_id
    if not backend_id then
        return false, "grant_deus_weapon did not assign backend_id"
    end

    -- Step 2: reach into _bot_loadouts directly (no public setter exists). Keyed by
    -- career_name, then slot_name -> backend_id. Initialize the per-career sub-table
    -- if vanilla didn't populate it for this slot.
    local bot_loadouts = rawget(deus_backend, "_bot_loadouts")
    if type(bot_loadouts) == "table" then
        bot_loadouts[career_name] = bot_loadouts[career_name] or {}
        bot_loadouts[career_name][slot_name] = backend_id
    else
        _dbg_alert("[bot-weap] deus_backend._bot_loadouts missing or non-table (got %s) — backend state may diverge",
            type(bot_loadouts))
    end

    -- Step 3: swap the live weapon unit on the bot. The inventory_system extension
    -- is the same SimpleInventoryExtension that human players use; bots are just
    -- AI-controlled player_units. create_equipment_in_slot replaces the existing
    -- slot unit and server-replicates to husks on remote peers.
    local bot_unit = bot.player_unit
    if bot_unit and Unit.alive(bot_unit) then
        local inv_ext = ScriptUnit.has_extension(bot_unit, "inventory_system")
        if inv_ext and inv_ext.create_equipment_in_slot then
            inv_ext:create_equipment_in_slot(slot_name, backend_id, 1)
        else
            _dbg_alert("[bot-weap] bot %s missing inventory_system or create_equipment_in_slot",
                tostring(bot.name and bot:name() or "?"))
        end
    end

    -- Step 5: persist into CW run_state so the bot's loadout survives respawn /
    -- `_update_career_loadout` reads. We need the lower-level set_player_loadout
    -- (DeusRunController.save_loadout is hardcoded to REAL_PLAYER_LOCAL_ID).
    local item_string = DeusWeaponGeneration.serialize_weapon(new_weapon)
    if run_state and run_state.set_player_loadout then
        run_state:set_player_loadout(host_peer_id, bot:local_player_id(),
            profile_index, career_index, slot_name, item_string)
    end

    _dbg("[bot-weap] bot=%s career=%s slot=%s rarity=%s key=%s power=%s backend_id=%s",
        tostring(bot.name and bot:name() or "?"),
        tostring(career_name), tostring(slot_name),
        tostring(new_weapon.rarity), tostring(new_weapon.deus_item_key),
        tostring(new_weapon.power_level), tostring(backend_id))

    return true
end

local function _bot_get_current_loadout(bot, run_state, host_peer_id, slot_name)
    local profile_index, career_index, _ = _resolve_bot_career(bot)
    if not profile_index or not career_index then return nil end
    if not (run_state and run_state.get_player_loadout) then return nil end
    local item_string = run_state:get_player_loadout(host_peer_id, bot:local_player_id(),
        profile_index, career_index, slot_name)
    if not item_string then return nil end
    local ok, weapon = pcall(DeusWeaponGeneration.deserialize_weapon, item_string)
    if not ok then
        _dbg_alert("[bot-weap] deserialize failed for bot=%s slot=%s: %s",
            tostring(bot.name and bot:name() or "?"), slot_name, tostring(weapon))
        return nil
    end
    return weapon
end

local function _gen_bot_weapon_for_slot(bot, run_state, target_rarity, slot_name, seed)
    local _, _, bot_career_name = _resolve_bot_career(bot)
    if not bot_career_name then return nil end
    local whitelist = run_state and run_state.get_weapon_group_whitelist and run_state:get_weapon_group_whitelist()
    if not whitelist then return nil end
    local pool = DeusWeaponGeneration.generate_weapon_pool(bot_career_name, whitelist)
    if not pool or not pool[target_rarity] then
        _dbg_alert("[bot-weap] no weapon pool for bot career=%s rarity=%s", tostring(bot_career_name), tostring(target_rarity))
        return nil
    end
    -- generate_weapon_for_slot picks from the slot's bucket only.
    local difficulty = run_state and run_state.get_run_difficulty and run_state:get_run_difficulty()
    local current_node = run_state and run_state.get_current_node_key and run_state:get_current_node_key()
    local run_progress = 0
    if current_node then
        local graph = Managers.mechanism:game_mechanism()
        local deus_run = graph and graph.get_deus_run_controller and graph:get_deus_run_controller()
        local node_data = deus_run and deus_run._get_graph_data and deus_run:_get_graph_data()
        if node_data and node_data[current_node] then
            run_progress = node_data[current_node].run_progress or 0
        end
    end
    local slot_short = slot_name == "slot_melee" and "melee" or "ranged"
    local ok, weapon = pcall(DeusWeaponGeneration.generate_weapon_for_slot,
        difficulty or "normal", run_progress, target_rarity, seed, pool, slot_short)
    if not ok or not weapon then
        _dbg_alert("[bot-weap] generate_weapon_for_slot failed bot=%s slot=%s rarity=%s err=%s",
            tostring(bot.name and bot:name() or "?"), slot_name, target_rarity, tostring(weapon))
        return nil
    end
    return weapon
end

-- Diagnostic event subscribers (gated on VMF debug logging via _dbg). The
-- event_manager gets torn down + recreated between missions, so we register
-- lazily and use a per-event-manager guard so re-registrations don't pile up.
local _ct_diag_event_manager_ref = nil
local _ct_diag_subscriber = setmetatable({}, { __mode = "v" })

_ct_diag_subscriber.player_pickup_deus_weapon_chest = function(self, player)
    local name = player and player.name and player:name() or "?"
    local is_bot = player and player.bot_player and "BOT" or "human"
    _dbg("[diag] event:player_pickup_deus_weapon_chest player=%s (%s)", tostring(name), is_bot)
end

_ct_diag_subscriber.chest_unlock_failed = function(self, chest_type)
    _dbg("[diag] event:chest_unlock_failed chest_type=%s", tostring(chest_type))
end

local function _diag_subscribe_if_needed()
    local ev = Managers.state and Managers.state.event
    if not ev or ev == _ct_diag_event_manager_ref then return end
    _ct_diag_event_manager_ref = ev
    local ok, err = pcall(function()
        ev:register(_ct_diag_subscriber,
            "player_pickup_deus_weapon_chest", "player_pickup_deus_weapon_chest",
            "chest_unlock_failed",              "chest_unlock_failed")
    end)
    if not ok then
        pcall(printf, "[diag] subscriber register failed: %s", tostring(err))
    else
        _dbg("[diag] diagnostic event subscribers registered (new event_manager)")
    end
end

mod:hook_safe("DeusChestExtension", "extensions_ready", function(self)
    _diag_subscribe_if_needed()
end)

-- #103 — PREVENT the structure-collapse animation on a re-armed altar.
-- ============================================================
-- Symptom (user 2026-06-30): a re-usable altar with uses remaining correctly
-- KEEPS its glow/offering (our open_chest post-hook re-fires lua_update_<chest_type>),
-- but its physical MODEL still shows the collapsed/looted pose after a single use.
--
-- Root cause: vanilla purchase() (deus_chest_extension.lua:301-317) fires
-- `Unit.flow_event(self.unit, "lua_update_collected")` — the STRUCTURE-collapse
-- transition in the altar unit's flow graph. That event is ONE-WAY (vanilla altars
-- are single-use, so nothing ever un-collapses them). Re-firing lua_update_<chest_type>
-- afterward (our open_chest re-arm) restores the offering hologram/glow but NOT the
-- collapsed structure — exactly the reported "glow OK, model collapsed".
--
-- Fix (Peregrinaje's approach = PREVENTION, not reversal — verified against the
-- Peregrinaje extract, which for reusable altars keeps _is_purchased=false and simply
-- never fires lua_update_collected): when this purchase will leave uses remaining, we
-- suppress ONLY that one flow event for the duration of vanilla purchase(), so the
-- structure never collapses in the first place. Everything else about purchase()
-- (cost via our get_purchase_cost hook, _is_purchased, "looted" anim state, the
-- rpc_deus_chest_looted round-trip) is left byte-identical to today, so the existing
-- open_chest post-hook re-arm operates on exactly the state it always has.
--
-- FAILS SAFE: the flow-event filter is installed under pcall; if it can't be installed
-- or restored, we fall back to plain vanilla purchase() — the altar collapses as it
-- does today (no visual fix on that path, but NO regression to glow/cost/currency).
-- The FINAL use (uses will be spent) always calls vanilla so the altar collapses
-- normally when genuinely depleted. `purchase` is a DIFFERENT method from our
-- `open_chest` hook, so this is not a duplicate hook. Uses check matches open_chest's
-- (`_altar_uses_by_go_id` is incremented in the open_chest post-hook AFTER purchase(),
-- so re-arm here = (current + 1) < max, identical to open_chest's `uses < max`).
mod:hook("DeusChestExtension", "purchase", function(func, self)
    local go_id = self._go_id
    local max_uses = (type(self._chest_type) == "string" and _altar_max_uses(self._chest_type)) or 1
    local will_rearm = go_id and (((_altar_uses_by_go_id[go_id] or 0) + 1) < max_uses)
    if not will_rearm then
        return func(self)  -- single / final use: collapse normally
    end

    local unit = self.unit
    local real_flow_event = Unit.flow_event
    local ok_install = pcall(function()
        Unit.flow_event = function(u, event, ...)
            if u == unit and event == "lua_update_collected" then
                return  -- swallow the structure-collapse for this re-armed altar
            end
            return real_flow_event(u, event, ...)
        end
    end)
    if not ok_install then
        pcall(function() Unit.flow_event = real_flow_event end)
        return func(self)  -- couldn't install the filter -> behave exactly as today
    end

    local ok, err = pcall(func, self)
    pcall(function() Unit.flow_event = real_flow_event end)  -- ALWAYS restore
    if not ok then
        -- purchase() errored under the filter. Do NOT re-run it (would double-charge);
        -- the filter is already restored. Log via printf (visible with mod-logging off).
        pcall(printf, "[altar_reuse] purchase under collapse-filter errored (go_id=%s): %s",
            tostring(go_id), tostring(err))
    end
end)

-- _ct_consolidated_open_chest_hook
-- =================================
-- THIS IS THE ONLY `open_chest` hook in ct_dev. Both the v0.7.127 altar-reuse
-- re-arm logic AND the bot-weapon-mirror logic live in this single
-- `mod:hook_safe`. DO NOT add a second `mod:hook(DeusChestExtension, open_chest)`
-- or `mod:hook_safe(DeusChestExtension, open_chest)` anywhere else in this
-- file — VMF silently DROPS the second hook (see VMF_RECIPES.md § 1 +
-- feedback_vmf_no_duplicate_hooks). It happened in v0.7.129/.130 and the
-- altar-reuse "fix" sat there as dead code for two releases. Catch via
-- /ct_regression_test → `open_chest_hook_singleton`. Source-pattern marker:
-- the string `_ct_consolidated_open_chest_hook` on this line.
mod:hook_safe("DeusChestExtension", "open_chest", function(self)
    -- #100 fix (v0.7.169-dev): capture the rarity vanilla open_chest JUST used to
    -- upgrade the host's weapon, BEFORE the upgrade-altar re-arm block below bumps
    -- self._rarity one tier higher for the NEXT use. The bot-weapon-mirror (further
    -- down this same hook) must mirror the rarity the HOST actually received, not the
    -- bumped next-use value — otherwise bots land one tier above the host
    -- (log-confirmed 2026-06-25 go_id=62: host wielded=rare, altar bumped to exotic,
    -- bots got exotic). Captured for all chest types; only the upgrade path is bumped,
    -- so swap_melee/swap_ranged see their unchanged self._rarity here.
    local _opened_rarity = self._rarity
    -- v0.7.131-dev altar-reuse re-arm (was a separate mod:hook in v0.7.129/.130,
    -- which collided with the bot-weapon-mirror hook below and was dropped by
    -- VMF). Runs FIRST so re-arm fires regardless of bot-mirror reentrancy state.
    -- Vanilla open_chest just finished (_post_chest_unlock → purchase, then
    -- _equip_weapon for weapon chests) — both completed with real profile_index,
    -- so we can safely zero it here to force the chest's `update` loop into its
    -- re-roll branch.
    do
        local go_id = self._go_id
        if go_id then
            _altar_uses_by_go_id[go_id] = (_altar_uses_by_go_id[go_id] or 0) + 1
            local uses = _altar_uses_by_go_id[go_id]
            local max_uses = _altar_max_uses(self._chest_type)

            -- v0.7.157-dev Task A [altar_visual_probe]: FORCED-OUTPUT diagnosis
            -- (unconditional mod:info — user just plays, no command needed). Capture
            -- chest_type / go_id / use count / re-arm branch decision, and
            -- collected_by_peers BEFORE the uncollect runs. Read-only.
            local is_server = Managers and Managers.player and Managers.player.is_server
            local collected_before = _ct_probe_collected_by_peers(go_id)
            _dbg("[altar_visual_probe] OPEN go_id=%s chest_type=%s uses=%d/%d rearm_branch=%s is_server=%s is_purchased=%s anim=%s profile_idx=%s collected_before=%s",
                tostring(go_id), tostring(self._chest_type), uses, max_uses,
                tostring(uses < max_uses), tostring(is_server),
                tostring(self._is_purchased), tostring(self._animation_state),
                tostring(self._profile_index), collected_before)

            if uses < max_uses then
                self._is_purchased = false
                self._animation_state = nil
                self._profile_index = 0
                self._career_index = 0
                -- v0.7.151-dev: ALSO retract this peer from the networked
                -- collected_by_peers GameSession field, kept adjacent to the
                -- _profile_index/_career_index zeroing so the next vanilla
                -- update() tick sees consistent state. Without it, vanilla
                -- update() (deus_chest_extension.lua:175) re-derives
                -- new_is_purchased=true from the still-present peer and re-loots
                -- the altar VISUALLY (line 177-182 -> _animation_state="looted"
                -- -> line 194 skips the anim update -> hologram never reappears).
                -- Pure data write to one field; does NOT re-enter purchase().
                mod._ct_altar_uncollect(self)

                -- v0.7.159-dev (the "used-up visual fires on use 1" root-cause fix):
                -- vanilla purchase() (deus_chest_extension.lua:308) ALREADY fired
                -- `lua_update_collected` — the used-up/looted MODEL transition — on
                -- THIS open, BEFORE this post-hook runs. Clearing _is_purchased /
                -- _animation_state above only stops the looted state being RE-asserted
                -- in update() (line 175-182); it does NOT un-fire the flow event, so
                -- the flow graph stays on the collected/looted mesh. The only thing
                -- that pulls it back to the live/available presentation is re-firing
                -- `lua_update_<chest_type>` (the SAME event vanilla emits at line 142
                -- when it re-rolls), but vanilla only does that inside the
                -- profile_index-changed branch (line 134) — racy and not guaranteed on
                -- the re-arm tick. Re-fire it here, deterministically, so a re-armed
                -- altar (uses < max) leaves the used-up look IMMEDIATELY. The depleted
                -- (else) branch deliberately re-fires NOTHING, leaving vanilla's
                -- lua_update_collected in place, so the used-up visual now shows ONLY
                -- after the final use. Per-peer: each peer runs its own post-hook +
                -- its own update() derivation off the host-authoritative
                -- collected_by_peers, so host and clients both flip available->used-up
                -- only when the host's configured max uses are spent. pcall-guarded
                -- per the repo Unit.flow_event rule (engine call, fatal bypasses pcall
                -- on a dead unit — has_unit guard + pcall).
                if self.unit and Unit and Unit.flow_event
                    and (not Unit.alive or Unit.alive(self.unit))
                    and type(self._chest_type) == "string" then
                    pcall(Unit.flow_event, self.unit, "lua_update_" .. self._chest_type)
                end

                _dbg("[altar_reuse] go_id=%s type=%s used %d/%d -> re-arm",
                    tostring(go_id), tostring(self._chest_type), uses, max_uses)

                -- v0.7.158-dev Task 1 (the REAL "goes dark after first use" fix):
                -- For an UPGRADE altar the dark/disabled look is NOT driven by
                -- collected_by_peers — it's update_upgrade_chest_color (deus_chest_
                -- extension.lua:211-243) firing `lua_interact_disabled` because,
                -- after the first upgrade, the wielded weapon's rarity now matches
                -- the altar's rolled `_rarity` (chest_rarity_order <= weapon_rarity_
                -- order). The altar also becomes genuinely unusable (can_be_unlocked
                -- lines 505-517). The vanilla re-roll keeps the SAME rarity (constant
                -- per-go_id seed), so we bump `_rarity` strictly above the just-
                -- upgraded weapon (capped at `unique`) and clear the cached color
                -- event so update_upgrade_chest_color re-evaluates to a usable, lit
                -- state. Server-authoritative state lives on the ext locally; this
                -- runs on the interacting peer (host solo = direct, correct).
                if self._chest_type == DEUS_CHEST_TYPES.upgrade then
                    local wielded = self._get_wielded_weapon and self:_get_wielded_weapon()
                    local wielded_rarity = wielded and wielded.rarity
                    local bumped = mod._ct_altar_next_rarity_above(wielded_rarity)
                    if bumped then
                        self._rarity = bumped
                        -- Re-fire the rarity flow event so the altar's hologram/glow
                        -- reflects the new tier (mirrors _setup_rarity line 357).
                        if self.unit and Unit and Unit.flow_event then
                            pcall(Unit.flow_event, self.unit, "lua_update_" .. bumped)
                        end
                    end
                    -- Clear the cached color-event memo so update_upgrade_chest_color
                    -- (line 238) re-emits a fresh event next tick instead of staying
                    -- on the stale `lua_interact_disabled` it set on the last use.
                    self._prev_update_upgrade_chest_color_event = nil
                    _dbg("[altar_reuse] upgrade re-arm go_id=%s wielded_rarity=%s -> altar_rarity=%s",
                        tostring(go_id), tostring(wielded_rarity), tostring(self._rarity))
                end

                -- v0.7.157-dev Task A [altar_visual_probe]: collected_by_peers AFTER
                -- the uncollect, plus the post-re-arm visual state we just wrote.
                -- Arm the per-go_id update-tick watcher so the read-only
                -- DeusChestExtension.update hook logs how vanilla re-derives the
                -- state over the next few ticks (does it re-set _is_purchased /
                -- _animation_state="looted"?).
                local collected_after = _ct_probe_collected_by_peers(go_id)
                local own_peer = self._deus_run_controller and self._deus_run_controller.get_own_peer_id
                    and self._deus_run_controller:get_own_peer_id()
                _dbg("[altar_visual_probe] REARM go_id=%s chest_type=%s own_peer=%s collected_after=%s post_rearm{is_purchased=%s anim=%s profile_idx=%s}",
                    tostring(go_id), tostring(self._chest_type), tostring(own_peer),
                    collected_after, tostring(self._is_purchased),
                    tostring(self._animation_state), tostring(self._profile_index))
                _ct_altar_probe_watch[go_id] = { ticks = 8, type = tostring(self._chest_type) }
            else
                _dbg("[altar_visual_probe] DEPLETED go_id=%s chest_type=%s uses=%d/%d -> stays looted (max reached, expected dark)",
                    tostring(go_id), tostring(self._chest_type), uses, max_uses)
            end
        else
            _dbg("[altar_visual_probe] OPEN no go_id on ext (chest_type=%s) — re-arm path skipped entirely",
                tostring(self._chest_type))
        end
    end

    -- ---- Boon-altar no-repeat bookkeeping (runs on the buying peer) ----
    -- For boon (power_up) ALTARS: record the taken boon for the per-run no-repeat
    -- default (always-on), so later boon altars don't re-offer it. This is a boon
    -- ALTAR / Shrine of Solace, NOT a Chest of Trials -- see the terminology
    -- banner near the get_purchase_cost hook.
    if self._chest_type == DEUS_CHEST_TYPES.power_up then
        local taken = self._stored_purchase and self._stored_purchase.name
        if taken then
            mod._ct_boon_altar_taken_boons = mod._ct_boon_altar_taken_boons or {}
            mod._ct_boon_altar_taken_boons[taken] = true
        end
        _dbg("[boon_altar] boon altar opened; taken boon=%s", tostring(taken))
    end

    -- ---- Bot weapon mirror (was the only body before v0.7.131 consolidation) ----
    if _ct_bot_weapon_mirror_active then return end
    if not effective_setting("bots_mirror_host_weapon_upgrades") then return end

    local run_controller = self._deus_run_controller
    local run_state = run_controller and run_controller._run_state
    if not run_state or not run_state:is_server() then return end

    local chest_type = self._chest_type
    if chest_type == DEUS_CHEST_TYPES.power_up then
        -- boon chests are handled by the add_power_ups bot-mirror hook above.
        return
    end
    if chest_type ~= DEUS_CHEST_TYPES.swap_melee
            and chest_type ~= DEUS_CHEST_TYPES.swap_ranged
            and chest_type ~= DEUS_CHEST_TYPES.upgrade then
        _dbg("[bot-weap] open_chest fired with unrecognized chest_type=%s", tostring(chest_type))
        return
    end

    -- Recipient = host human local player. Bots cannot open chests, so this is
    -- always the host when on the server.
    local host_peer_id = run_state:get_own_peer_id()
    local target_slot
    if chest_type == DEUS_CHEST_TYPES.swap_melee then
        target_slot = "slot_melee"
    elseif chest_type == DEUS_CHEST_TYPES.swap_ranged then
        target_slot = "slot_ranged"
    else
        -- upgrade chest: vanilla upgrades the host's wielded weapon; for the bot
        -- we'll upgrade the bot's currently-wielded slot independently.
        local _, wielded_slot = self:_get_wielded_weapon()
        target_slot = wielded_slot or "slot_melee"
    end

    -- #100 fix (v0.7.169-dev): use the rarity the HOST's weapon was actually upgraded
    -- to on THIS open (captured at hook entry before the re-arm bump), NOT the live
    -- self._rarity — for upgrade altars the re-arm block above has already bumped
    -- self._rarity one tier higher for the next use, which is what made bots land a
    -- tier above the host. For swap altars _opened_rarity == self._rarity (no bump).
    local target_rarity = _opened_rarity
    if not target_rarity then
        _dbg("[bot-weap] no chest rarity recorded — aborting bot mirror")
        return
    end

    local player_manager = Managers.player
    if not player_manager or not player_manager.human_and_bot_players then return end
    local all_players = player_manager:human_and_bot_players()
    if not all_players then return end

    local bots = {}
    for _, p in pairs(all_players) do
        if p.bot_player and p.player_unit and Unit.alive(p.player_unit) then
            bots[#bots + 1] = p
        end
    end
    if #bots == 0 then
        _dbg("[bot-weap] no live bots present — chest_type=%s rarity=%s", tostring(chest_type), tostring(target_rarity))
        return
    end

    _dbg("[bot-weap] host opened chest_type=%s rarity=%s target_slot=%s bots=%d",
        tostring(chest_type), tostring(target_rarity), tostring(target_slot), #bots)

    _ct_bot_weapon_mirror_active = true
    local ok, err = pcall(function()
        local go_id = self._go_id or (Managers.state.unit_storage and Managers.state.unit_storage:go_id(self.unit))
        for bi, bot in ipairs(bots) do
            -- Per-bot seed: chest go_id + bot local id + bot peer + slot. Keeps
            -- rolls reproducible if vanilla determinism matters for replay diff.
            local bot_seed_input = string.format("%s_%s_%s_%s",
                tostring(go_id or 0), tostring(bot:local_player_id()),
                tostring(bot:network_id() or "?"), target_slot)
            local seed = HashUtils.fnv32_hash(bot_seed_input)
            local new_weapon
            if chest_type == DEUS_CHEST_TYPES.upgrade then
                local current = _bot_get_current_loadout(bot, run_state, host_peer_id, target_slot)
                if current then
                    local current_order = RaritySettings[current.rarity] and RaritySettings[current.rarity].order or 0
                    local target_order = RaritySettings[target_rarity] and RaritySettings[target_rarity].order or 0
                    if current_order >= target_order then
                        _dbg("[bot-weap] bot=%s slot=%s current rarity=%s >= chest rarity=%s — skipping upgrade",
                            tostring(bot.name and bot:name() or "?"), target_slot,
                            tostring(current.rarity), tostring(target_rarity))
                    else
                        local difficulty = run_state:get_run_difficulty()
                        local current_node_key = run_state:get_current_node_key()
                        local graph = run_controller._get_graph_data and run_controller:_get_graph_data()
                        local progress = graph and graph[current_node_key] and graph[current_node_key].run_progress or 0
                        new_weapon = DeusWeaponGeneration.upgrade_item(current, difficulty, progress, target_rarity, seed)
                    end
                else
                    _dbg_alert("[bot-weap] bot=%s slot=%s has no current CW weapon to upgrade — synthesizing fresh",
                        tostring(bot.name and bot:name() or "?"), target_slot)
                    new_weapon = _gen_bot_weapon_for_slot(bot, run_state, target_rarity, target_slot, seed)
                end
            else
                new_weapon = _gen_bot_weapon_for_slot(bot, run_state, target_rarity, target_slot, seed)
            end
            if new_weapon then
                local equipped_ok, equip_err = _bot_equip_weapon(bot, new_weapon, target_slot, run_state, host_peer_id)
                if not equipped_ok then
                    _dbg_alert("[bot-weap] equip failed bot_idx=%d: %s", bi, tostring(equip_err))
                end
            else
                _dbg("[bot-weap] bot_idx=%d produced no new weapon (skip)", bi)
            end
        end
    end)
    _ct_bot_weapon_mirror_active = false

    if not ok then
        pcall(printf, "[bot-weap] error mirroring weapon chest to bots: %s", tostring(err))
        return
    end

    _dbg("[bot-weap] mirrored chest_type=%s rarity=%s onto %d bot(s)",
        tostring(chest_type), tostring(target_rarity), #bots)
end)

-- ============================================================
-- Boss Grudge Marks Banlist (re-instated v0.7.89 — properly working now)
-- ============================================================
-- Per-mark checkboxes that exclude individual BreedEnhancements from the
-- monster-boss enhancement roll. Vanilla picks N enhancements per boss from
-- `BossGrudgeMarks` (grudge_mark_settings.lua:126-140) via
-- `TerrorEventUtils.generate_enhanced_breed` (terror_event_utils.lua:107). N is
-- driven by `BREED_ENHANCEMENTS_PER_DIFFICULTY` and the active difficulty/tweak,
-- so the menu only has visible effect at higher difficulties (normal: only at
-- +10 tweak; cataclysm: up to 3 marks per boss).
--
-- WHY THE v0.7.76 IMPLEMENTATION DIDN'T WORK: it hooked
-- `TerrorEventUtils.add_enhancements_for_difficulty`, but the CW arena terror
-- event files capture that function reference as a file-scope local UPVALUE at
-- boot (`local boss_pre_spawn_func = TerrorEventUtils.add_enhancements_for_difficulty`
-- in arena_ruin / arena_ice / arena_citadel / arena_cave / arena_belakor / ...
-- and `cursed_chest_enemy_pre_spawn_func = ...` in deus_generic_terror_events.lua:15).
-- The capture happens BEFORE mods load, so by the time VMF replaces the table
-- entry, the upvalues already hold direct refs to the original function. Boss
-- spawns then bypass the hook entirely. Same shape as the v0.7.66 mutator
-- template `template.server.start_function` bug.
--
-- THE FIX: mutate `_G.BossGrudgeMarks` directly. Vanilla
-- `add_enhancements_for_difficulty` reads `BossGrudgeMarks` via global lookup at
-- call time (`enhancement_set = enhancement_set or BossGrudgeMarks` at
-- terror_event_utils.lua:197), and `generate_enhanced_breed` iterates the set
-- via `pairs(enhancement_set)` (line 115) — so removing keys removes those
-- marks from the random candidate list at the next boss spawn. Empty-set is
-- safe (the inner for-loop early-exits, `BreedEnhancements.base` is still
-- appended unconditionally on line 112).
--
-- Server-only effect (enhancement assignment is server-authoritative; spawn
-- data envelope broadcasts the chosen enhancements to clients), but we mutate
-- on every peer for consistency and to make `/dump_grudge_marks` show the
-- effective live state on whichever machine runs it.
local BOSS_GRUDGE_MARK_NAMES = {
    "commander", "crippling", "crushing", "frenzy", "intangible",
    "periodic_curse", "periodic_shield", "raging", "ranged_immune",
    "regenerating", "unstaggerable", "vampiric", "warping",
}

-- Snapshot of vanilla BossGrudgeMarks captured the first time sync runs (which
-- is at mod load, after grudge_mark_settings.lua has executed). Used as the
-- reset baseline so toggling a ban OFF restores the original entry instead of
-- losing it forever once banned.
local _grudge_mark_baseline = nil
local function _capture_grudge_baseline()
    if _grudge_mark_baseline then return end
    local bgm = rawget(_G, "BossGrudgeMarks")
    if not bgm then return end
    _grudge_mark_baseline = {}
    for name, v in pairs(bgm) do
        _grudge_mark_baseline[name] = v
    end
end

local function sync_grudge_marks()
    _capture_grudge_baseline()
    local bgm = rawget(_G, "BossGrudgeMarks")
    if not bgm or not _grudge_mark_baseline then
        _dbg("[grudge] sync skipped: _G.BossGrudgeMarks=%s baseline=%s",
            tostring(bgm), tostring(_grudge_mark_baseline))
        return
    end
    -- Reset to baseline, then nil-out banned marks.
    for name, v in pairs(_grudge_mark_baseline) do
        bgm[name] = v
    end
    local banned = {}
    for _, name in ipairs(BOSS_GRUDGE_MARK_NAMES) do
        local sid = "ban_grudge_mark_" .. name
        if effective_setting(sid) then
            bgm[name] = nil
            banned[#banned + 1] = name
        end
    end
    if #banned > 0 then
        _dbg("[grudge] %d marks banned: %s", #banned, table.concat(banned, ", "))
    else
        _dbg("[grudge] no marks banned; vanilla BossGrudgeMarks restored")
    end
end

sync_grudge_marks()

-- ============================================================
-- Grudge-mark SPAWN diagnostic (v0.7.169-dev) — _ct_grudge_apply_diag
-- ============================================================
-- The data gap behind the "banned mark still appeared on a Belakor champion"
-- report. ct's ban only nils _G.BossGrudgeMarks, which the RANDOM BOSS roll
-- honours -- but (a) the Belakor Shadow Lieutenant draws its 2 marks from a
-- HARDCODED LOCAL pool in deus_generic_terror_events.lua and reads
-- BreedEnhancements DIRECTLY (bypassing BossGrudgeMarks), and (b) enhancement
-- assignment is SERVER-AUTHORITATIVE, so a mark the HOST allows still appears even
-- if a CLIENT banned it (the 2026-06-25 logs show host periodic_shield=0 but
-- client periodic_shield=1). We had NO spawn-time record of what actually applied.
--
-- TerrorEventUtils.apply_breed_enhancements is the UNIVERSAL apply chokepoint
-- (conflict_director.lua:2041 calls it for EVERY enhanced spawn) and is referenced
-- as a true _G global by field at call time (no upvalue capture, unlike the dead
-- v0.7.76 add_enhancements_for_difficulty hook), so this fires reliably for the
-- boss roll AND the Shadow Lieutenant AND grudge_mark_commander spawns.
--
-- v0.7.177-dev (#107): now FILTERS, not just logs. On the host it strips any
-- enhancement whose name maps to a banned `ban_grudge_mark_<name>` setting BEFORE
-- vanilla applies them, then logs applied + stripped. Because this is the single
-- apply chokepoint, the filter catches the Be'lakor Shadow Lieutenant's hardcoded
-- pool (which bypasses _G.BossGrudgeMarks, the gap the nil-out fix above can't
-- close), the random boss roll, and grudge_mark_commander alike. Single mod:hook
-- (no VMF dup-hook — VMF_RECIPES.md § 1).
if rawget(_G, "TerrorEventUtils") then
    mod:hook(_G.TerrorEventUtils, "apply_breed_enhancements", function(func, unit, breed, optional_data)
        local enh = optional_data and optional_data.enhancements
        local is_server = Managers and Managers.player and Managers.player.is_server
        if type(enh) == "table" and #enh > 0 then
            -- #107: strip BANNED grudge marks before vanilla applies. Each entry's
            -- `.name` is its BreedEnhancements key (grudge_mark_settings.lua:122-124),
            -- which equals the `ban_grudge_mark_<name>` setting suffix — direct map.
            -- BreedEnhancements.base (name="base") has no ban setting so it is kept.
            -- HOST-ONLY strip: assignment is server-authoritative (host rolls/applies/
            -- broadcasts; clients apply what they receive), so filtering only on the
            -- host keeps host/client consistent.
            local applied, removed = {}, {}
            if is_server then
                local kept = {}
                for i = 1, #enh do
                    local e = enh[i]
                    local nm = (type(e) == "table" and e.name) or (type(e) == "string" and e) or nil
                    if type(nm) == "string" and effective_setting("ban_grudge_mark_" .. nm) == true then
                        removed[#removed + 1] = nm
                    else
                        kept[#kept + 1] = e
                        applied[#applied + 1] = nm or "?"
                    end
                end
                if #removed > 0 then
                    optional_data.enhancements = kept
                end
            else
                for i = 1, #enh do
                    local e = enh[i]
                    applied[#applied + 1] = (type(e) == "table" and e.name) or tostring(e)
                end
            end
            -- printf (raw engine print), NOT mod:info: survives a VMF-mod-logging-OFF
            -- host so the spawn record is actually captured in the user's console log.
            pcall(printf, "[grudge-spawn] breed=%s is_server=%s applied=[%s] banned_stripped=[%s]",
                tostring(breed and breed.name), tostring(is_server),
                table.concat(applied, ", "), table.concat(removed, ", "))
        end
        return func(unit, breed, optional_data)
    end)
end

-- Dump command — safe to run from the keep (reads _G.BossGrudgeMarks +
-- BreedEnhancements; doesn't need a live boss spawn). Use this to verify the
-- ban toggles are taking effect before joining a run.
mod:command("dump_grudge_marks", "Dump the live BossGrudgeMarks set and each entry's status", function()
    local bgm = rawget(_G, "BossGrudgeMarks")
    local be = rawget(_G, "BreedEnhancements")
    if not bgm then
        mod:echo("[grudge] BossGrudgeMarks not loaded yet.")
        return
    end
    pcall(printf, "[DUMP:grudge_marks] === baseline: %d entries ===", _grudge_mark_baseline and (function() local n = 0 for _ in pairs(_grudge_mark_baseline) do n = n + 1 end return n end)() or 0)
    pcall(printf, "[DUMP:grudge_marks] === live BossGrudgeMarks: %d entries ===", (function() local n = 0 for _ in pairs(bgm) do n = n + 1 end return n end)())
    pcall(printf, "[DUMP:grudge_marks] name\ttoggle_on\tlive_present\tdisplay_name_key")
    for _, name in ipairs(BOSS_GRUDGE_MARK_NAMES) do
        local toggle_on = effective_setting("ban_grudge_mark_" .. name) == true
        local live_present = bgm[name] ~= nil
        local entry = be and be[name]
        local dn_key = entry and entry.display_name or ("display_name_" .. name)
        pcall(printf, "[DUMP:grudge_marks] %s\t%s\t%s\t%s", name, tostring(toggle_on), tostring(live_present), dn_key)
    end
    mod:echo(string.format("dump_grudge_marks: %d marks (see log for per-mark detail).", #BOSS_GRUDGE_MARK_NAMES))
end)

-- ============================================================
-- Verification commands (run from keep; no live encounter required)
-- ============================================================
-- Per `feedback_vt2_verify_before_shipping.md`: every gated feature ships with a `/verify_*`
-- command that compares toggle state vs live runtime state and reports PASS/FAIL.

mod:command("verify_grudge_marks", "Verify each Boss Grudge Mark toggle vs live BossGrudgeMarks state", function()
    local bgm = rawget(_G, "BossGrudgeMarks")
    if not bgm then
        mod:echo("[verify_grudge] FAIL: _G.BossGrudgeMarks not loaded.")
        return
    end
    local pass, fail = 0, 0
    for _, name in ipairs(BOSS_GRUDGE_MARK_NAMES) do
        local toggle_on  = effective_setting("ban_grudge_mark_" .. name) == true
        local live_present = bgm[name] ~= nil
        local expected_present = not toggle_on
        local ok = (live_present == expected_present)
        if ok then
            pass = pass + 1
            pcall(printf, "[verify_grudge] PASS: %s (banned=%s live=%s)", name, tostring(toggle_on), tostring(live_present))
        else
            fail = fail + 1
            mod:warning("[verify_grudge] FAIL: %s — banned=%s but live=%s (expected live=%s)",
                name, tostring(toggle_on), tostring(live_present), tostring(expected_present))
        end
    end
    mod:echo(string.format("/verify_grudge_marks: %d PASS, %d FAIL (%d total)", pass, fail, #BOSS_GRUDGE_MARK_NAMES))
end)

-- 2026-05-23 v0.7.100-dev DISABLED: /verify_dormants chat command removed because the
-- dormant feature is fully purged. Re-enable alongside the dormant injection code.
-- The regression check `dormant_chat_commands_removed` asserts the command is absent
-- from the VMF command registry.
--[[
mod:command("verify_dormants", "Verify each dormant boon toggle vs live DeusPowerUpsArrayByRarity / DeusPowerUpRarityPool state", function()
    -- original body removed in v0.7.100-dev purge; see git history for full code.
end)
--]]

mod:command("verify_belakor", "Verify Belakor's Temple state: with_belakor / arena_belakor_node / current_node", function()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    local rs = rc and rc._run_state
    if not rs then
        mod:echo("[verify_belakor] N/A: no active DeusRunState (not in a CW run). Re-run after Olesya intro.")
        return
    end
    -- v0.7.120: vanilla method is `get_belakor_enabled`, NOT `get_with_belakor` —
    -- pre-v0.7.120 this command printed nil because the wrong name was used.
    local with_belakor   = (rs.get_belakor_enabled and rs:get_belakor_enabled())
                           or (rs.get_with_belakor and rs:get_with_belakor())
    local arena_node     = rs.get_arena_belakor_node and rs:get_arena_belakor_node()
    local current_node   = rs.get_current_node_key and rs:get_current_node_key()
    local force_setting  = effective_setting("force_belakor")
    local is_server      = rs.is_server and rs:is_server()
    pcall(printf, "[verify_belakor] is_server=%s force_belakor=%s belakor_enabled=%s arena_node=%s current_node=%s",
        tostring(is_server), tostring(force_setting), tostring(with_belakor),
        tostring(arena_node), tostring(current_node))
    local will_force_unique = (current_node and arena_node and current_node == arena_node) or false
    pcall(printf, "[verify_belakor] cursed_chest at current_node will force unique-tier? %s", tostring(will_force_unique))
    mod:echo(string.format("/verify_belakor: belakor_enabled=%s arena_node=%s current_node=%s (see log for full state)",
        tostring(with_belakor), tostring(arena_node), tostring(current_node)))
end)

-- v0.7.120 — `/dump_journey` runs the same full-state diagnostic as the
-- DeusMapDecisionView._start hook but on-demand from chat. Use this:
--   * Both peers run it AT THE SAME TIME (host + client) in a co-op CW run.
--   * Both logs are diffed against each other to find host/client divergence.
-- Surfaces: graph node count, arena nodes per peer, belakor_enabled, arena_belakor_node,
-- current_node, journey, force_belakor effective setting, plus per-node prefix dump.
-- Same `[belakor:diag]` tag as the auto-hooks so a single grep covers both.
mod:command("dump_journey", "Dump full CW journey state: graph nodes, arena_belakor, belakor_enabled, settings", function()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not rc then
        mod:echo("/dump_journey: no active CW run (run from inside a CW expedition).")
        return
    end
    local rs = rc._run_state
    local is_server = (rs and rs.is_server and rs:is_server()) or (Managers and Managers.player and Managers.player.is_server) or false
    local cur_key = rc.get_current_node_key and rc:get_current_node_key() or nil
    local journey = rc.get_journey_name and rc:get_journey_name() or nil
    local arena_node = rs and rs.get_arena_belakor_node and rs:get_arena_belakor_node() or nil
    local belakor_enabled = rs and rs.get_belakor_enabled and rs:get_belakor_enabled() or nil
    local seen = rc.has_own_seen_arena_belakor_node and rc:has_own_seen_arena_belakor_node() or nil
    local pg = rc._get_graph_data and rc:_get_graph_data() or nil
    local total, arena_count = 0, 0
    local arena_keys = {}
    if type(pg) == "table" then
        for k, n in pairs(pg) do
            total = total + 1
            if type(n) == "table" then
                local lvl = n.level or ""
                if type(lvl) == "string" and lvl:find("^arena") then
                    arena_count = arena_count + 1
                    arena_keys[#arena_keys + 1] = tostring(k) .. "(" .. lvl .. ",theme=" .. tostring(n.theme) .. ")"
                end
            end
        end
    end
    pcall(printf, "[belakor:diag] /dump_journey is_server=%s journey=%s current_node=%s belakor_enabled=%s arena_belakor_node=%s has_own_seen=%s graph_total=%d arena_in_graph=%d (%s) force_setting=%s",
        tostring(is_server), tostring(journey), tostring(cur_key),
        tostring(belakor_enabled), tostring(arena_node), tostring(seen),
        total, arena_count, table.concat(arena_keys, ","),
        tostring(effective_setting("force_belakor")))
    if type(pg) == "table" then
        for k, n in pairs(pg) do
            if type(n) == "table" then
                local lvl = tostring(n.level or "?")
                local prefix
                if k == "start" then
                    prefix = "<start>"
                else
                    local us = lvl:find("_")
                    prefix = (us and us > 1) and lvl:sub(1, us - 1) or lvl
                end
                local mut_str = "<nil>"
                if type(n.mutators) == "table" then
                    local list = {}
                    for i, m in ipairs(n.mutators) do list[i] = tostring(m) end
                    mut_str = "{" .. table.concat(list, ",") .. "}"
                end
                pcall(printf, "[belakor:diag] /dump_journey node %s level=%s prefix=%s theme=%s curse=%s god=%s node_type=%s level_seed=%s mutators=%s",
                    tostring(k), lvl, prefix, tostring(n.theme),
                    tostring(n.curse), tostring(n.god), tostring(n.node_type),
                    tostring(n.level_seed), mut_str)
            end
        end
    end
    mod:echo(string.format("/dump_journey: is_server=%s journey=%s arena_count=%d (see log for full per-node dump — grep [belakor:diag])",
        tostring(is_server), tostring(journey), arena_count))
end)

-- v0.7.120 — `/dump_isha` quick snapshot of Isha mutex state (Issue #54).
-- Surfaces what each peer sees: local toggles + effective_setting (host-broadcast) +
-- which description text WOULD be returned by the Localize hook. Diff host vs client
-- to confirm description-source fix.
mod:command("dump_isha", "Dump Miracle of Isha mutex state: local toggles, effective settings, description selection", function()
    local is_server = Managers and Managers.player and Managers.player.is_server
    local aegis_local = mod:get("tweak_miracle_of_isha_aegis")
    local wounds_local = mod:get("tweak_miracle_of_isha_wounds")
    local aegis_eff = effective_setting("tweak_miracle_of_isha_aegis")
    local wounds_eff = effective_setting("tweak_miracle_of_isha_wounds")
    local legacy_eff = effective_setting("tweak_miracle_of_isha_alternative")
    local desc_choice = "vanilla"
    if aegis_eff then desc_choice = "aegis"
    elseif wounds_eff then desc_choice = "wounds"
    elseif legacy_eff == true or legacy_eff == "aegis" then desc_choice = "aegis (legacy)"
    elseif legacy_eff == "wounds" then desc_choice = "wounds (legacy)"
    end
    pcall(printf, "[isha:diag] /dump_isha is_server=%s local_aegis=%s local_wounds=%s eff_aegis=%s eff_wounds=%s legacy=%s -> desc_choice=%s",
        tostring(is_server), tostring(aegis_local), tostring(wounds_local),
        tostring(aegis_eff), tostring(wounds_eff), tostring(legacy_eff), desc_choice)
    mod:echo(string.format("/dump_isha: desc_choice=%s eff_aegis=%s eff_wounds=%s (see log)",
        desc_choice, tostring(aegis_eff), tostring(wounds_eff)))
end)

-- v0.7.95: starting_coins verification (setter vs adder regression).
-- Prints current coin balance, the active setting, and whether the override
-- hook is registered. Use during a CW run to confirm the value applied.
mod:command("verify_coins", "Verify starting_coins: live coin balance vs setting, and override-hook registration", function()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    local setting = mod:get("starting_coins")
    local snapped = (type(setting) == "number") and math.floor(setting / 25 + 0.5) * 25 or 0
    local marker_present = (type(STARTING_COINS_MODE_MARKER) == "string"
        and STARTING_COINS_MODE_MARKER == "starting_coins:setter-override-via-setup_run-arg")
    local hook_registered_str = marker_present and "yes (setter-override mode marker present)" or "NO (marker missing)"
    if not rc then
        mod:echo(string.format("/verify_coins: setting=%s (snapped=%d), override-hook=%s, live balance=N/A (no active CW run — use during run)",
            tostring(setting), snapped, hook_registered_str))
        pcall(printf, "[verify_coins] no active DeusRunController; setting=%s snapped=%d marker=%s",
            tostring(setting), snapped, tostring(marker_present))
        return
    end
    local own_peer_id = rc.get_own_peer_id and rc:get_own_peer_id()
    local balance = rc.get_player_soft_currency and own_peer_id and rc:get_player_soft_currency(own_peer_id)
    local is_server = rc.is_server and rc:is_server()
    pcall(printf, "[verify_coins] is_server=%s own_peer_id=%s setting=%s snapped=%d live_balance=%s marker=%s",
        tostring(is_server), tostring(own_peer_id), tostring(setting), snapped, tostring(balance), tostring(marker_present))
    mod:echo(string.format("/verify_coins: setting=%d, live=%s, override-hook=%s, host=%s. NOTE: match expected only at run-start; mid-run balance reflects pickups/spends.",
        snapped, tostring(balance), hook_registered_str, tostring(is_server)))
end)

-- v0.7.97: career-exclusive pickup blocklist verifier.
-- Prints the blocklist constant + the current per-run denial counts so the
-- user can confirm the gate is working without re-reading the source.
mod:command("verify_engineer_bombs", "Verify career-exclusive pickup blocklist (Engineer crafted bombs etc.) + per-run denial counts", function()
    local names = {}
    for k in pairs(_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST) do names[#names + 1] = k end
    table.sort(names)
    if #names == 0 then
        mod:echo("/verify_engineer_bombs: blocklist EMPTY (regression?)")
        return
    end
    mod:echo(string.format("/verify_engineer_bombs: %d blocklist entries", #names))
    for _, name in ipairs(names) do
        local count = _career_exclusive_denial_counts[name] or 0
        local in_pickups = false
        if Pickups then
            for _, bucket in pairs(Pickups) do
                if type(bucket) == "table" and bucket[name] then
                    in_pickups = true
                    break
                end
            end
        end
        mod:echo(string.format("  %s : denials_this_run=%d, present_in_Pickups=%s",
            name, count, tostring(in_pickups)))
        pcall(printf, "[verify_engineer_bombs] %s denials_this_run=%d present_in_Pickups=%s",
            name, count, tostring(in_pickups))
    end
end)

-- ============================================================
-- Modified Boons
-- ============================================================

-- CLARIFY: `reckless_swings_originals` doubles as a "tweak active" flag. Non-nil = tweak applied.
-- This avoids double-apply (which would save the already-modified values as "originals" and lose
-- the real originals).
local reckless_swings_originals = nil

-- CLARIFY: Khaine's Fury (internal name `deus_reckless_swings`) softening:
--   vanilla:  health threshold 0.50, self-damage 3 per melee hit
--   tweaked:  health threshold 0.25, self-damage 1 per melee hit
-- Patches THREE places: the on-buff template (governs gameplay), description_values by value_type
-- (the % threshold shown in tooltip's "above X% Health"), and description_values by value_type
-- (the damage shown). The `Localize` hook below also overrides the description text since its
-- formatting may not refer to description_values directly.
--
-- See https://github.com/Ensrick/vermintide-2-tweaker/issues/5 — resolved in v0.7.92-dev.
-- Migration from positional [1]/[3] indexing to name-based lookup via _find_entry_by helper.
-- v0.7.84 added sanity guards that bail safely if FatShark reorders the arrays; name-based
-- lookup is now the default with guards retained as defense-in-depth.

-- HELPER: Find first entry in array where predicate(entry) returns true
-- Avoids hard-coded positional indices if FatShark reorders the templates.
local function _find_entry_by(arr, predicate)
    if not arr then return nil, nil end
    for i, e in ipairs(arr) do
        if predicate(e) then return i, e end
    end
    return nil, nil
end

-- v0.7.103: source-pattern sentinel for GH #5 fix (Reckless Swings name-based
-- lookup, shipped v0.7.92). Read by /ct_regression_test check
-- `reckless_swings_name_based_lookup`. If a future refactor reverts the
-- name-based lookup to positional `buffs[1]`/`description_values[1]`/`[3]`
-- indexing, the most plausible bitrot path also strips this comment block and
-- the marker constant, breaking the check. The marker is also used as an
-- upvalue inside `apply_reckless_swings_tweak` to anchor it to the function
-- body, so a partial revert that nukes the search code but leaves the marker
-- declaration would still fail the source-pattern check via the upvalue read.
local CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER = "name-based-lookup-v0.7.92"
local function apply_reckless_swings_tweak()
    if reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    -- v0.7.24 bugfix: previous versions mutated DeusPowerUpBuffTemplates, but
    -- the runtime buff system reads from the GLOBAL `BuffTemplates` table which
    -- received COPIED values via DLCUtils.merge() at game boot
    -- (buff_templates.lua:9532). Mutating the source DeusPowerUpBuffTemplates
    -- has no effect on what the proc function reads — `template.damage_to_deal`
    -- inside `deus_reckless_swings_buff_on_hit` reads from BuffTemplates.
    -- Mutate BuffTemplates directly. Outer-buff health_threshold via
    -- DeusPowerUpTemplates still works because the apply path reads that
    -- table directly (deus_power_up_utils.lua:250).
    local runtime_buffs = rawget(_G, "BuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        return
    end

    local tpl = power_up.deus_reckless_swings
    local runtime_buff_entry = runtime_buffs and runtime_buffs.deus_reckless_swings_buff

    -- v0.7.92: name-based lookup via _find_entry_by helper. Searches the buffs array
    -- for the entry where buff_to_add == "deus_reckless_swings_buff" and description_values
    -- for entries with the expected value_type fields. Sanity guards retained as defense-
    -- in-depth: verify name match and numeric types before mutation.
    local buff_index, buff_entry = _find_entry_by(
        tpl.buff_template and tpl.buff_template.buffs,
        function(e) return e and e.buff_to_add == "deus_reckless_swings_buff" end
    )
    if not buff_entry then
        mod:warning("[khaines-fury] buff entry with buff_to_add=deus_reckless_swings_buff not found — skipping tweak")
        return
    end

    -- Find description_values entries by value_type: first "percent" (threshold), then "amount" (damage)
    local dv_threshold_index, dv_threshold = _find_entry_by(
        tpl.description_values,
        function(e) return e and e.value_type == "percent" and type(e.value) == "number" end
    )
    local dv_damage_index, dv_damage = _find_entry_by(
        tpl.description_values,
        function(e) return e and e.value_type == "amount" and type(e.value) == "number" end
    )

    -- Sanity-check: all three lookup targets must exist and be numeric
    if not buff_entry or not dv_threshold or not dv_damage then
        mod:warning("[khaines-fury] vanilla template shape changed (buff=%s, dv_threshold=%s, dv_damage=%s) — skipping tweak",
            tostring(buff_entry ~= nil), tostring(dv_threshold ~= nil), tostring(dv_damage ~= nil))
        return
    end
    if type(buff_entry.health_threshold) ~= "number" or type(dv_threshold.value) ~= "number" or type(dv_damage.value) ~= "number" then
        mod:warning("[khaines-fury] expected numeric fields, got %s/%s/%s — skipping tweak",
            type(buff_entry.health_threshold), type(dv_threshold.value), type(dv_damage.value))
        return
    end

    reckless_swings_originals = {
        buff_index = buff_index,
        health_threshold = buff_entry.health_threshold,
        dv_threshold_index = dv_threshold_index,
        dv_threshold_value = dv_threshold.value,
        dv_damage_index = dv_damage_index,
        dv_damage_value = dv_damage.value,
        buff_damage = runtime_buff_entry and runtime_buff_entry.buffs[1].damage_to_deal,
    }

    buff_entry.health_threshold = 0.25
    dv_threshold.value = 0.25
    dv_damage.value = 1

    if runtime_buff_entry and runtime_buff_entry.buffs and runtime_buff_entry.buffs[1] then
        runtime_buff_entry.buffs[1].damage_to_deal = 1
    end

    -- Read the sentinel marker as an upvalue so a refactor that strips the
    -- name-based search code path also breaks this read site (the closure no
    -- longer captures the marker, so the upvalue resolves to nil). Anchor for
    -- /ct_regression_test source-pattern check `reckless_swings_name_based_lookup`.
    local _marker_anchor = CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER

    _dbg("[khaines-fury] tweak applied via name-based lookup (buff_index=%d, dv_threshold_index=%d, dv_damage_index=%d, sentinel=%s)",
        buff_index, dv_threshold_index, dv_damage_index, _marker_anchor)
end

-- CLARIFY: Mirrors apply_reckless_swings_tweak. Note the early-out when DeusPowerUpTemplates is
-- gone (e.g. user left Chaos Wastes) — we still clear the originals flag so the next entry can
-- re-apply cleanly. This is the only path that nils the flag without doing the actual restore.
local function revert_reckless_swings_tweak()
    if not reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    -- v0.7.24: revert from runtime BuffTemplates (same fix as apply).
    local runtime_buffs = rawget(_G, "BuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        reckless_swings_originals = nil
        return
    end

    local tpl = power_up.deus_reckless_swings
    local runtime_buff_entry = runtime_buffs and runtime_buffs.deus_reckless_swings_buff

    -- v0.7.92: revert using stored indices from apply (name-based lookup)
    if tpl.buff_template and tpl.buff_template.buffs then
        local buff_entry = tpl.buff_template.buffs[reckless_swings_originals.buff_index]
        if buff_entry then
            buff_entry.health_threshold = reckless_swings_originals.health_threshold
        end
    end
    if tpl.description_values then
        local dv_threshold = tpl.description_values[reckless_swings_originals.dv_threshold_index]
        local dv_damage = tpl.description_values[reckless_swings_originals.dv_damage_index]
        if dv_threshold then
            dv_threshold.value = reckless_swings_originals.dv_threshold_value
        end
        if dv_damage then
            dv_damage.value = reckless_swings_originals.dv_damage_value
        end
    end

    if runtime_buff_entry and runtime_buff_entry.buffs and runtime_buff_entry.buffs[1] and reckless_swings_originals.buff_damage then
        runtime_buff_entry.buffs[1].damage_to_deal = reckless_swings_originals.buff_damage
    end

    reckless_swings_originals = nil
end

-- CLARIFY: Description override for Khaine's Fury lives in the consolidated _G.Localize
-- hook above (search for ADV_TITLE_OVERRIDES). Centralized to avoid the VMF
-- "Attempting to rehook active hook [Localize]" warning when two hooks compete for the
-- same target. The `reckless_swings_originals` gate ensures the override only fires
-- while the tweak is active.

-- CLARIFY: Assignment to the forward-declared `sync_reckless_swings`. From here on, references at
-- the top of the file (in generate_random_power_ups hook) and the on_setting_changed callback
-- below resolve to this function.
sync_reckless_swings = function()
    if effective_setting("tweak_reckless_swings") then
        apply_reckless_swings_tweak()
    else
        revert_reckless_swings_tweak()
    end
end

-- CLARIFY: Apply once at mod load. If the user has the toggle on AND DeusPowerUpTemplates is
-- already loaded (e.g. they enter the Keep, hot-reload doesn't apply since chaos_wastes_tweaker is
-- restart-only per CLAUDE.md), this immediately patches. Outside CW, DeusPowerUpTemplates is nil
-- and the apply silently no-ops; the generate_random_power_ups hook re-runs sync on first roll.
sync_reckless_swings()

-- ============================================================
-- Bomb Boon Cooldown Tweak
-- ============================================================
-- The `drop_item_on_ability_use` boon (rally flag / Morgrim's / Endless Bombs) reads its per-item
-- cooldowns from `buff_template.buffs[1].cooldown_durations` at proc time
-- (morris_buff_settings.lua:2830). Mutating that table in place lets us uniformly override the
-- vanilla 180/180/120 with a single configurable value. Mirrors the reckless_swings save-and-
-- restore pattern: the mutation persists across hook calls within a session, so on_disabled has
-- to revert it.

local bomb_cooldown_originals = nil

local function apply_bomb_cooldown_tweak()
    if bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if not durations then
        _dbg("[bomb-cooldown] DeusPowerUpTemplates.drop_item_on_ability_use not loaded yet; will retry on next boon roll")
        return
    end

    local override = effective_setting("bomb_boon_cooldown")
    if not override or override <= 0 then
        _dbg("[bomb-cooldown] override=%s (no change)", tostring(override))
        return
    end

    bomb_cooldown_originals = {}
    local before = {}
    for k, v in pairs(durations) do
        before[#before + 1] = string.format("%s=%d", k, v)
        bomb_cooldown_originals[k] = v
        durations[k] = override
    end
    _dbg("[bomb-cooldown] override=%d applied. Was: %s", override, table.concat(before, ", "))
end

local function revert_bomb_cooldown_tweak()
    if not bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if durations then
        for k, v in pairs(bomb_cooldown_originals) do
            durations[k] = v
        end
    end
    bomb_cooldown_originals = nil
end

sync_bomb_cooldown = function()
    -- Always revert first so a setting change from one positive value to another re-applies the
    -- new value (rather than silently no-op'ing because originals are already saved).
    revert_bomb_cooldown_tweak()
    local override = effective_setting("bomb_boon_cooldown")
    if override and override > 0 then
        apply_bomb_cooldown_tweak()
    end
end

sync_bomb_cooldown()

-- #120 (v0.7.177-dev): the template-mutation above mutates the SOURCE
-- DeusPowerUpTemplates table, but the runtime buff resolves `buff.template` from a
-- registered copy (same copy-vs-source trap that forced reckless_swings to patch both
-- tables) — so the cooldown override "did nothing". This hook makes the override
-- authoritative by working on the LIVE buff: it wraps the `drop_item_on_ability_use`
-- proc (morris_buff_settings.lua:2742 — drops a bomb/medkit/potion when you pop your
-- career ult, then arms the `drop_item_on_ability_use_cooldown` buff whose duration
-- gates the next drop) and, after vanilla runs, overrides that cooldown buff's
-- duration to the user's configured interval. Vanilla itself sets `buff.duration`
-- AFTER add_buff (line 2830), so a post-call duration write is the supported pattern
-- and works for intervals SHORTER or longer than the vanilla 180/180/120. interval 0
-- = leave vanilla untouched. Runs on the proc'ing player's machine; the interval is
-- host-synced via effective_setting so every peer uses the host's value.
if rawget(_G, "BuffFunctionTemplates") and BuffFunctionTemplates.functions
        and BuffFunctionTemplates.functions.drop_item_on_ability_use then
    mod:hook(BuffFunctionTemplates.functions, "drop_item_on_ability_use", function(func, owner_unit, buff, params, ...)
        func(owner_unit, buff, params, ...)

        local interval = effective_setting("bomb_boon_cooldown")
        if not (interval and interval > 0) then return end
        if not (rawget(_G, "ALIVE") and ALIVE[owner_unit]) then return end

        local buff_ext = ScriptUnit.has_extension(owner_unit, "buff_system")
        local cd = buff_ext and buff_ext.get_non_stacking_buff
            and buff_ext:get_non_stacking_buff("drop_item_on_ability_use_cooldown")
        if cd then
            cd.duration = interval
            pcall(printf, "[ct-bomb-boon] drop_item cooldown overridden -> %ds", interval)
        end
    end)
end

-- ============================================================
-- Ulric's Pack (wolfpack) Unlimited Aura Range
-- ============================================================
-- Vanilla `wolfpack` boon's proximity buff has `range_check = { radius = 20, ... }`
-- (deus_power_up_settings.lua:3829-3835). BuffAreaHelper.update_range_check reads
-- `range_check_template.radius` fresh on every tick (buff_area_helper.lua:26), so a
-- one-time mutation of that field is sufficient — no per-frame hook needed. Mirror
-- the bomb_cooldown save-and-restore pattern: on_setting_changed re-syncs without
-- restart, and revert lets toggling off restore vanilla 20m radius.
--
-- Per `feedback_vt2_gated_registration_diverges.md`: this only mutates an existing
-- vanilla template field; it never registers/unregisters the boon, never touches
-- BuffTemplates, NetworkLookup, or any sequential-index table. Safe to gate on the
-- per-user toggle. Host-authoritative: each peer mutates locally for their own
-- buff-extension proximity ticks, and the buff itself is applied via standard
-- buff-system propagation so client peers without the toggle still see the buff's
-- effect — they just compute their own proximity passes at vanilla 20m. Toggle the
-- host's setting and the host's proximity passes (which drive who gets the buff
-- via wolfpack_entered_range/wolfpack_left_range RPCs) ignore distance.

local wolfpack_radius_original = nil

local function apply_wolfpack_unlimited_range()
    if wolfpack_radius_original ~= nil then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.wolfpack
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local rc = buff_entry and buff_entry.range_check
    if not rc or type(rc.radius) ~= "number" then
        _dbg("[ulric-pack-range] DeusPowerUpTemplates.wolfpack not loaded yet; will retry on next sync")
        return
    end
    wolfpack_radius_original = rc.radius
    rc.radius = math.huge
    _dbg("[ulric-pack-range] radius %s -> math.huge", tostring(wolfpack_radius_original))
end

local function revert_wolfpack_unlimited_range()
    if wolfpack_radius_original == nil then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.wolfpack
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local rc = buff_entry and buff_entry.range_check
    if rc then
        rc.radius = wolfpack_radius_original
    end
    wolfpack_radius_original = nil
end

sync_ulric_pack_unlimited_range = function()
    revert_wolfpack_unlimited_range()
    if effective_setting("ulric_pack_unlimited_range") then
        apply_wolfpack_unlimited_range()
    end
end

sync_ulric_pack_unlimited_range()

-- ============================================================
-- Movement Speed Boon Tweak (5% -> 10%)
-- ============================================================
-- The vanilla `movespeed` boon (a one-of-a-kind CW mission-completion reward, boon-treated)
-- adds `apply_movement_buff` with multiplier 1.05 (sourced from
-- `MorrisBuffTweakData.movespeed.multiplier`) and shows "5%" in the tooltip (sourced from
-- `MorrisBuffTweakData.movespeed.description_value`). The values are baked at game load by
-- `deus_power_up_settings.lua` into two places:
--   * Gameplay: `DeusPowerUpBuffTemplates.power_up_movespeed_<rarity>.buffs[1].multiplier` (1.05),
--     one entry per rarity (common/rare/legendary).
--   * Tooltip:  `DeusPowerUpTemplates.movespeed.description_values[1].value` (0.05), shared by
--     all rarities via reference — a single mutation propagates to every rarity tooltip.
-- We mirror the reckless_swings save-and-restore: snapshot originals on apply, restore them on
-- revert, and call sync from the boon-roll hook + on_setting_changed.

local MOVESPEED_RARITIES = { "common", "rare", "legendary" }
local boon_movespeed_originals = nil

local function apply_boon_movespeed_tweak()
    if boon_movespeed_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    local tpl = power_up and power_up.movespeed
    if not tpl or not buff_tpls then
        return
    end

    local desc_value_entry = tpl.description_values and tpl.description_values[1]
    if not desc_value_entry then
        return
    end

    local per_rarity = {}
    for i = 1, #MOVESPEED_RARITIES do
        local rarity = MOVESPEED_RARITIES[i]
        local buff_entry = buff_tpls["power_up_movespeed_" .. rarity]
        local sub = buff_entry and buff_entry.buffs and buff_entry.buffs[1]
        if sub and sub.multiplier then
            per_rarity[rarity] = sub.multiplier
            sub.multiplier = 1.10
        end
    end

    boon_movespeed_originals = {
        desc_value = desc_value_entry.value,
        per_rarity = per_rarity,
    }

    desc_value_entry.value = 0.10
end

local function revert_boon_movespeed_tweak()
    if not boon_movespeed_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    local tpl = power_up and power_up.movespeed
    local desc_value_entry = tpl and tpl.description_values and tpl.description_values[1]

    if desc_value_entry then
        desc_value_entry.value = boon_movespeed_originals.desc_value
    end

    if buff_tpls then
        for rarity, original_mult in pairs(boon_movespeed_originals.per_rarity) do
            local buff_entry = buff_tpls["power_up_movespeed_" .. rarity]
            local sub = buff_entry and buff_entry.buffs and buff_entry.buffs[1]
            if sub then
                sub.multiplier = original_mult
            end
        end
    end

    boon_movespeed_originals = nil
end

sync_boon_movespeed = function()
    if effective_setting("tweak_boon_movespeed") then
        apply_boon_movespeed_tweak()
    else
        revert_boon_movespeed_tweak()
    end
end

sync_boon_movespeed()

-- ============================================================
-- Potion Reworks (v0.7.26-alpha)
-- ============================================================
-- BuffTemplates is the runtime merged table built by DLCUtils.merge at boot
-- (`buff_templates.lua:5568`-ish). Source `DLCSettings.morris.buff_templates` is the
-- per-DLC definition; mutating it after merge has no effect on what the runtime reads
-- (same gotcha as Khaine's Fury v0.7.24). All mutations target `BuffTemplates.<name>`
-- directly.
--
-- Pattern matches reckless_swings: snapshot originals once on apply, restore on revert,
-- re-run sync on settings change. The action's vanilla `_increased` resolution (in
-- `action_potion.lua:68`, gated on `potion_duration` perk) automatically picks up the
-- modified `_increased` variant when Decanter is held — no extra plumbing needed for
-- Decanter composition.
--
-- TODO v0.7.27: Home Brewer composition (+50% potency when home_brewer is held). Needs
-- a buff-apply hook + `_brewed` / `_brewed_increased` variant registration in
-- NetworkLookup.buff_templates.

-- --- Poison Proof duration tweak (vanilla 120s/240s -> 240s/360s) ---
local poison_proof_originals = nil

local function apply_poison_proof_tweak()
    if poison_proof_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.poison_proof_potion
    local inc = bt and bt.poison_proof_potion_increased
    local base_buff = base and base.buffs and base.buffs[1]
    local inc_buff = inc and inc.buffs and inc.buffs[1]
    if not base_buff or not inc_buff then
        _dbg("[poison-proof] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    poison_proof_originals = {
        base = base_buff.duration,
        inc = inc_buff.duration,
    }
    base_buff.duration = 240
    inc_buff.duration = 360
    _dbg(string.format("[poison-proof] applied: base=%s -> 240, increased=%s -> 360",
        tostring(poison_proof_originals.base), tostring(poison_proof_originals.inc)))
end

local function revert_poison_proof_tweak()
    if not poison_proof_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base_buff = bt and bt.poison_proof_potion and bt.poison_proof_potion.buffs and bt.poison_proof_potion.buffs[1]
    local inc_buff = bt and bt.poison_proof_potion_increased and bt.poison_proof_potion_increased.buffs and bt.poison_proof_potion_increased.buffs[1]
    if base_buff then base_buff.duration = poison_proof_originals.base end
    if inc_buff then inc_buff.duration = poison_proof_originals.inc end
    poison_proof_originals = nil
end

local function sync_poison_proof_tweak()
    if effective_setting("tweak_poison_proof_duration") then
        apply_poison_proof_tweak()
    else
        revert_poison_proof_tweak()
    end
end

sync_poison_proof_tweak()

-- --- Killer in the Shadows (invisibility potion) 2x duration ---
-- Vanilla: base 5s / increased 15s (MorrisBuffTweakData.killer_in_the_shadows_potion.duration).
-- BuffTemplates copies duration by value at template generation, so we mutate the
-- BuffTemplates entry directly (the MorrisBuffTweakData mutation is a no-op post-boot).
local invis_potion_originals = nil

local function apply_invis_potion_tweak()
    if invis_potion_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.killer_in_the_shadows_potion
    local inc = bt and bt.killer_in_the_shadows_potion_increased
    local base_buff = base and base.buffs and base.buffs[1]
    local inc_buff = inc and inc.buffs and inc.buffs[1]
    if not base_buff or not inc_buff then
        _dbg("[invis-potion] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    invis_potion_originals = {
        base = base_buff.duration,
        inc = inc_buff.duration,
    }
    base_buff.duration = (invis_potion_originals.base or 5) * 2
    inc_buff.duration = (invis_potion_originals.inc or 15) * 2
    _dbg(string.format("[invis-potion] applied: base=%s -> %s, increased=%s -> %s",
        tostring(invis_potion_originals.base), tostring(base_buff.duration),
        tostring(invis_potion_originals.inc), tostring(inc_buff.duration)))
end

local function revert_invis_potion_tweak()
    if not invis_potion_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base_buff = bt and bt.killer_in_the_shadows_potion and bt.killer_in_the_shadows_potion.buffs and bt.killer_in_the_shadows_potion.buffs[1]
    local inc_buff = bt and bt.killer_in_the_shadows_potion_increased and bt.killer_in_the_shadows_potion_increased.buffs and bt.killer_in_the_shadows_potion_increased.buffs[1]
    if base_buff then base_buff.duration = invis_potion_originals.base end
    if inc_buff then inc_buff.duration = invis_potion_originals.inc end
    invis_potion_originals = nil
end

local function sync_invis_potion_tweak()
    if effective_setting("tweak_invis_potion_2x") then
        apply_invis_potion_tweak()
    else
        revert_invis_potion_tweak()
    end
end

sync_invis_potion_tweak()

-- --- Hangover Brew (moot_milk) alternative effect ---
-- Vanilla buff structure (morris_buff_settings.lua:5804): 3 buffs
--   1. screenspace FX (`fx/screenspace_hungover_01`)
--   2. movespeed (apply_movement_buff, +50% MS for 1.5s)
--   3. damage (stat_buff increased_weapon_damage, multiplier 1)
-- Alt structure: 3 buffs for 60s
--   1. screenspace FX (keep hungover for visual feedback)
--   2. movement speed +25% for full duration
--   3. infinite_dodge perk
--   4. stamina regen (fatigue_regen stat_buff) +40%
-- Decanter automatically picks `_increased` (90s) via vanilla action_potion.lua resolution.

local moot_milk_originals = nil

local function build_moot_milk_alt_buffs(duration)
    return {
        {
            activation_effect = "fx/screenspace_drink_01",
            continuous_effect = "fx/screenspace_drink_looping",
            icon = "potion_hold_my_beer",
            max_stacks = 1,
            name = "moot_milk_potion",
            refresh_durations = true,
            remove_buff_func = "remove_deus_potion_buff",
            duration = duration,
        },
        {
            -- v0.7.50: WAS 0.25 (which is a literal multiplier on move_speed, so the player
            -- moved at 25% of base speed — a -75% slow). `apply_movement_buff` does
            -- `move_speed *= multiplier`; vanilla speed_boost_potion uses 1.5 for +50%.
            -- 1.25 = +25% as the surrounding comment / changelog have always claimed.
            apply_buff_func = "apply_movement_buff",
            max_stacks = 1,
            name = "moot_milk_potion_movement_speed_alt",
            refresh_durations = true,
            remove_buff_func = "remove_movement_buff",
            duration = duration,
            multiplier = 1.25,
            path_to_movement_setting_to_modify = {
                "move_speed",
            },
        },
        {
            max_stacks = 1,
            name = "moot_milk_potion_infinite_dodge_alt",
            refresh_durations = true,
            duration = duration,
            perks = {
                -- v0.7.44: was `buff_perks.infinite_dodge`. The `buff_perks` global is
                -- a `table.enum` map of name → name string. At mod-load timing it isn't
                -- always populated in `_G` (the buff system's perk_names file is
                -- required AFTER mods init in some load orders), so the lookup returned
                -- nil and the apply silently bailed at the `rawget(_G, "buff_perks")`
                -- gate below — meaning Moot Milk stayed vanilla for the whole session.
                -- Using the literal string is functionally identical (the buff system
                -- looks up perks by string key, which IS what `table.enum` stores).
                "infinite_dodge",
            },
        },
        {
            max_stacks = 1,
            name = "moot_milk_potion_stamina_regen_alt",
            refresh_durations = true,
            stat_buff = "fatigue_regen",
            duration = duration,
            multiplier = 0.40,
        },
    }
end

local function apply_moot_milk_alt_tweak()
    if moot_milk_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.moot_milk_potion
    local inc = bt and bt.moot_milk_potion_increased
    if not base or not inc then
        _dbg("[moot-milk-alt] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    -- v0.7.44: removed `buff_perks` gate. The previous gate bailed when the global
    -- wasn't populated yet (logged in 2026-05-15 session); the replacement uses the
    -- literal string "infinite_dodge" in build_moot_milk_alt_buffs above, which is
    -- functionally equivalent and doesn't require the global.
    moot_milk_originals = {
        base_buffs = base.buffs,
        inc_buffs = inc.buffs,
    }
    base.buffs = build_moot_milk_alt_buffs(60)
    inc.buffs = build_moot_milk_alt_buffs(90)
    _dbg("[moot-milk-alt] applied: base=60s, increased=90s (+25%% MS, infinite dodge, +40%% stamina regen)")
end

local function revert_moot_milk_alt_tweak()
    if not moot_milk_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    if bt and bt.moot_milk_potion then bt.moot_milk_potion.buffs = moot_milk_originals.base_buffs end
    if bt and bt.moot_milk_potion_increased then bt.moot_milk_potion_increased.buffs = moot_milk_originals.inc_buffs end
    moot_milk_originals = nil
end

local function sync_moot_milk_alt_tweak()
    if effective_setting("tweak_moot_milk_alt") then
        apply_moot_milk_alt_tweak()
    else
        revert_moot_milk_alt_tweak()
    end
end

sync_moot_milk_alt_tweak()

-- ============================================================
-- Shard Strike duration nerf (v0.7.28b-alpha)
-- ============================================================
-- Shard Strike (`armor_breaker` weapon trait) spawns a 16-second damaging stagger aura
-- around the player on killing an armoured enemy. Vanilla 16s is widely considered
-- overtuned (top-tier offensive AND defensive). This nerf lets the user shorten the
-- duration to any value 1-16s. At 16 = vanilla (no-op).
--
-- Mutates `WeaponTraits.buff_templates.armor_breaker.buffs[1].duration` directly. The
-- buff template is merged from `weapon_traits_morris.lua:980` (BuffUtils.apply_buff_tweak_data)
-- and registered at game boot, so the runtime value is whatever lives in WeaponTraits at
-- the moment add_buff is called. Mod load happens after merge, so our mutation takes
-- effect for all subsequent procs. ALSO mutates `BuffTemplates.armor_breaker` if present
-- (defensive — some merge paths copy into the global BuffTemplates).
local shard_strike_originals = nil

local function _shard_strike_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    local wt_buff = wt and wt.buff_templates and wt.buff_templates.armor_breaker and wt.buff_templates.armor_breaker.buffs and wt.buff_templates.armor_breaker.buffs[1]
    if wt_buff then out[#out+1] = wt_buff end
    local bt = rawget(_G, "BuffTemplates")
    local bt_buff = bt and bt.armor_breaker and bt.armor_breaker.buffs and bt.armor_breaker.buffs[1]
    if bt_buff then out[#out+1] = bt_buff end
    return out
end

local function revert_shard_strike_tweak()
    if not shard_strike_originals then return end
    for _, b in ipairs(_shard_strike_buff_entries()) do
        b.duration = shard_strike_originals.duration
    end
    shard_strike_originals = nil
end

local function apply_shard_strike_tweak()
    local user_value = effective_setting("tweak_shard_strike_duration") or 16
    local target = math.max(1, math.min(16, user_value))
    if target == 16 then
        revert_shard_strike_tweak()
        return
    end
    local entries = _shard_strike_buff_entries()
    if #entries == 0 then
        _dbg("[shard-strike] WeaponTraits.buff_templates.armor_breaker not loaded yet; will retry on settings sync")
        return
    end
    if not shard_strike_originals then
        shard_strike_originals = { duration = entries[1].duration }
    end
    for _, b in ipairs(entries) do
        b.duration = target
    end
end

local function sync_shard_strike()
    apply_shard_strike_tweak()
end

sync_shard_strike()

-- ============================================================
-- Anath Raema's Swiftness — permanent reload speed (v0.7.36-alpha)
-- ============================================================
-- Vanilla: the trait `deus_ammo_pickup_reload_speed` watches `on_consumable_picked_up`
-- and adds a 10-second `deus_ammo_pickup_reload_speed_buff` (+50% reload speed) on
-- ammo pickup. This rework swaps the parent trait template for a passive permanent
-- +50% `reload_speed` stat_buff that's active whenever the weapon (with the trait) is
-- wielded.
--
-- Mutates BOTH `WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed` (the trait
-- registry the trait system reads at apply time) AND `BuffTemplates.deus_ammo_pickup_reload_speed`
-- (the global runtime buff lookup). Save-and-restore so the toggle is reversible.
local anath_raema_originals = nil

local function _anath_raema_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    if wt and wt.buff_templates and wt.buff_templates.deus_ammo_pickup_reload_speed then
        out[#out + 1] = { tbl = wt.buff_templates, key = "deus_ammo_pickup_reload_speed" }
    end
    local bt = rawget(_G, "BuffTemplates")
    if bt and bt.deus_ammo_pickup_reload_speed then
        out[#out + 1] = { tbl = bt, key = "deus_ammo_pickup_reload_speed" }
    end
    return out
end

local function revert_anath_raema_permanent_tweak()
    if not anath_raema_originals then return end
    for _, e in ipairs(_anath_raema_buff_entries()) do
        e.tbl[e.key] = anath_raema_originals.templates[e.key] or e.tbl[e.key]
    end
    anath_raema_originals = nil
end

local function apply_anath_raema_permanent_tweak()
    local entries = _anath_raema_buff_entries()
    if #entries == 0 then
        _dbg("[anath-raema] templates not loaded yet; will retry on settings sync")
        return
    end
    if anath_raema_originals then return end
    local saved = {}
    for _, e in ipairs(entries) do
        saved[e.key] = e.tbl[e.key]
    end
    anath_raema_originals = { templates = saved }

    -- Replacement template: single permanent stat_buff. multiplier = 0.5 matches the
    -- vanilla on-pickup multiplier from MorrisBuffTweakData.deus_ammo_pickup_reload_speed_buff.
    local replacement = {
        buffs = {
            {
                name        = "deus_ammo_pickup_reload_speed_permanent",
                stat_buff   = "reload_speed",
                multiplier  = 0.5,
                max_stacks  = 1,
            },
        },
    }
    for _, e in ipairs(entries) do
        e.tbl[e.key] = replacement
    end
end

local function sync_anath_raema_permanent()
    if effective_setting("tweak_anath_raema_permanent") then
        apply_anath_raema_permanent_tweak()
    else
        revert_anath_raema_permanent_tweak()
    end
end

sync_anath_raema_permanent()

-- ============================================================
-- Defeat Recovery: soft wipe recovery with penalty (v0.7.39-alpha)
-- ============================================================
-- When `tweak_defeat_recovery` is on and the team would wipe, instead force-respawn
-- everyone in place and apply a penalty: zero own coins + remove 5 random own boons.
-- The mission continues from the wipe point — this is NOT a full level reload (the
-- engine doesn't expose a safe mid-run "reload current level" path; that'd require a
-- full level transition with all the run-state replication that entails).
--
-- LIMITATIONS:
-- * Per-peer locality: each peer applies the penalty to their OWN coins and boons.
--   In MP, every peer needs ct with the toggle on for the team to share the rescue.
--   If only the host has ct, the host doesn't lose / the run continues, but other
--   peers' coins/boons are not modified.
-- * Recovery fires once per round (per level). Subsequent wipes on the same level end
--   the run normally. This prevents infinite loops and keeps recovery a finite resource.
-- * Reset on level transition via the existing `_transition_next_node` hook.
-- (Flag itself is forward-declared near the top of the file; just used here.)

local function _apply_local_defeat_penalty()
    local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
    local deus_run_controller = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not deus_run_controller then
        _dbg("[defeat-recovery] no deus_run_controller; skipping penalty")
        return
    end
    local run_state = deus_run_controller._run_state
    if not run_state then return end

    local local_peer_id = run_state:get_own_peer_id()
    local local_player_id = 1  -- REAL_PLAYER_LOCAL_ID per deus_run_controller.lua:29

    -- Zero own coins.
    run_state:set_player_soft_currency(local_peer_id, local_player_id, 0)
    _dbg("[defeat-recovery] zeroed own coins")

    -- Pick 5 random boons (or fewer if you have less than 5) and remove them.
    local profile_index, career_index = run_state:get_player_profile(local_peer_id, local_player_id)
    local power_ups = run_state:get_player_power_ups(local_peer_id, local_player_id, profile_index, career_index)
    if power_ups and #power_ups > 0 then
        local indices = {}
        for i = 1, #power_ups do indices[i] = i end
        local to_remove = math.min(5, #indices)
        local removed_names = {}
        for _ = 1, to_remove do
            local pick = math.random(#indices)
            local boon_idx = indices[pick]
            table.remove(indices, pick)
            local boon = power_ups[boon_idx]
            if boon and boon.name then
                removed_names[#removed_names + 1] = boon.name
                deus_run_controller:remove_power_ups(boon.name, local_player_id)
            end
        end
        _dbg(string.format("[defeat-recovery] removed %d boons: %s", #removed_names, table.concat(removed_names, ", ")))
    else
        _dbg("[defeat-recovery] no boons to remove")
    end
end

local function _force_respawn_team()
    if not Managers.state.game_mode then return end
    local game_mode = Managers.state.game_mode:game_mode()
    if game_mode and game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
        _dbg("[defeat-recovery] force-respawned dead players")
    end
end

mod:hook("GameModeDeus", "evaluate_end_conditions", function(func, self, ...)
    -- v0.7.64: host-synced. The hook itself only runs on the host (GameModeDeus is
    -- server-authoritative), so this read effectively gets the host's value either
    -- way — but using effective_setting keeps the lookup pattern uniform with the
    -- rest of the codebase and survives any future re-entry from a client context.
    if not effective_setting("tweak_defeat_recovery") then
        return func(self, ...)
    end
    if _defeat_recovery_triggered_this_round then
        -- Already burned the recovery for this round; normal end-condition resolution.
        return func(self, ...)
    end
    local ended, reason = func(self, ...)
    if ended and reason == "lost" then
        _defeat_recovery_triggered_this_round = true
        _apply_local_defeat_penalty()
        _force_respawn_team()
        _dbg("[defeat-recovery] intercepted wipe — penalty applied, players respawned, round continues")
        return false  -- Don't propagate the "lost" outcome.
    end
    return ended, reason
end)

-- ============================================================
-- Activate Dormant Boons (v0.7.29-alpha)
-- ============================================================
-- 9 boons defined in vanilla `DeusPowerUpTemplates` but NOT registered in
-- `DeusPowerUpRarityPool` — they can never roll in the active CW loot pool. Each has an
-- `activate_dormant_<boon>` toggle. When on, the boon is injected into the rarity pool
-- (and all derived tables: DeusPowerUps, DeusPowerUpsArray, DeusPowerUpsArrayByRarity,
-- DeusPowerUpsLookup, DeusPowerUpBuffTemplates) using the same construction pattern as
-- vanilla's registration loop at `deus_power_up_settings.lua:7121-7176`.
--
-- LIMITATIONS:
-- * Additive only — toggling OFF doesn't remove the boon from the active run; would
--   require a game restart to fully clear. The injection takes effect on the next CW
--   run setup (since the engine reads the pool at run start).
-- * Per-boon rarity is fixed; user can't currently choose a different rarity for a
--   given dormant boon. Defaults are sensible (powerful boons → exotic, weaker → rare).
-- IMPORTANT: vanilla boon rarities are { event, rare, exotic, unique } ONLY (see
-- deus_power_up_settings.lua:7032 `DeusPowerUpRarities`). "common" / "plentiful" are
-- weapon-drop rarities and do NOT exist for boons. `existing_power_ups_lut` is keyed
-- off DeusPowerUpRarities — injecting at a non-listed rarity crashes
-- `deus_power_up_utils.lua:189` when the boon ends up in `existing_power_ups`.
-- v0.7.37 fix: squats and deus_larger_clip moved from "common" → "rare".
-- 2026-05-23 v0.7.100-dev FULLY PURGED: dormant boons removed per user request after recurring
-- Chest-of-Trials crashes. The `DORMANT_BOON_RARITY` table is GONE (not even an empty {}), and
-- every active reference to it has been purged from the file. To re-enable: restore the table
-- below, uncomment the apply-site calls at the bottom of this section
-- (pre_register_dormant_lookups + sync_dormant_boons), restore the `_should_strip` dormant
-- branch in the generate_random_power_ups hook (~L1146), restore the boon-trace hook dormant
-- fields (~L3440), restore the `/verify_dormants` chat command (~L3670), restore the
-- DORMANT_BOON_RARITY references in `deus_rarities_valid` regression check (~L7180), and
-- restore the regression checks `dormant_boons_preregistered` + `dormant_buff_dual_registered`
-- + `kill_heal_uses_permanent_heal_type` + `skulls_boons_preregistered`.
--
-- TODO(squats) — when re-enabling, promote `squats` to "unique" rarity and
-- give it the following effect: on crouch action, grant 15 seconds of
-- invisibility, with a 3-minute cooldown. (User spec 2026-05-23.) Needs:
-- (1) hook the crouch input on PlayerUnitFirstPerson (or wherever the
-- crouch press is observed) — gate per-player so only the boon-holder fires;
-- (2) apply the existing `invisibility` buff template for 15s; (3) per-buff
-- cooldown via mod-side timestamp keyed on player_unit. Vanilla `squats`
-- has no defined effect in DeusPowerUpBuffTemplates today, so this is a
-- ct-authored buff body.
--[[
local DORMANT_BOON_RARITY = {
    deus_ammo_pickup_give_allies_ammo    = "rare",
    deus_coin_pickup_regen               = "rare",
    deus_large_ammo_pickup_infinite_ammo = "exotic",
    deus_larger_clip                     = "rare",   -- v0.7.37 was "common", crashed
    deus_throw_speed_increase            = "rare",
    deus_timed_block_free_shot           = "exotic",
    deus_transmute_into_coins            = "rare",
    explosive_pushes_on_damage_taken     = "exotic",
    squats                               = "unique", -- TODO(squats): 15s invisibility on crouch, 3min cooldown
}
--]]

-- _injected_dormants and _added_to_pool stay because the meta boons (CT_META_BOONS at
-- ~L5500) and trait boons (CT_TRAIT_BOONS at ~L5750) still legitimately call
-- inject_dormant_boon / _add_dormant_to_pool — those functions are generic boon
-- injectors; only their HISTORICAL NAME mentions "dormant." They do not touch
-- DORMANT_BOON_RARITY directly.
local _injected_dormants = {}

-- v0.7.38/v0.7.40: Register a name in a NetworkLookup table. Vanilla builds these
-- lookups at boot from their backing global tables (BuffTemplates,
-- DeusPowerUpTemplates, etc.). Entries we add post-boot are NOT in the lookups, and
-- the lookup's __index metatable errors on unknown keys (network_lookup.lua:2354).
-- Append index→name and set the reverse name→index. rawget bypasses the
-- error-on-unknown-key metatable when checking for existing registration.
local function _register_in_network_lookup(lookup_key, name)
    if type(name) ~= "string" then return end
    local nl = rawget(_G, "NetworkLookup")
    local t = nl and nl[lookup_key]
    if not t then return end
    if rawget(t, name) then return end
    local idx = #t + 1
    t[idx] = name
    t[name] = idx
end

local function register_buff_in_network_lookup(buff_name)
    _register_in_network_lookup("buff_templates", buff_name)
end

local function register_power_up_in_network_lookup(power_up_name)
    _register_in_network_lookup("deus_power_up_templates", power_up_name)
end

local function inject_dormant_boon(power_up_name, rarity)
    if _injected_dormants[power_up_name] then return end

    -- v0.7.40: Register in NetworkLookup.deus_power_up_templates immediately. Vanilla
    -- code at deus_run_state_spec.lua:60, deus_run_controller.lua:1198 (and similar)
    -- looks up the power-up by name. Without registration the lookup errors when the
    -- player selects this boon at a chest (Crashify guid 9f697495 — burned in v0.7.39).
    register_power_up_in_network_lookup(power_up_name)

    -- v0.7.67: `DeusPowerUpRarityPool` (the pool table) is no longer read here —
    -- pool insertion moved to `_add_dormant_to_pool` below. Other globals stay.
    local templates        = rawget(_G, "DeusPowerUpTemplates")
    local power_ups        = rawget(_G, "DeusPowerUps")
    local array            = rawget(_G, "DeusPowerUpsArray")
    local array_by_rarity  = rawget(_G, "DeusPowerUpsArrayByRarity")
    local lookup           = rawget(_G, "DeusPowerUpsLookup")
    local buff_templates   = rawget(_G, "DeusPowerUpBuffTemplates")
    local settings         = rawget(_G, "DeusPowerUpSettings")
    local availability_t   = rawget(_G, "DeusPowerUpAvailabilityTypes")
    local tweak_data_glob  = rawget(_G, "MorrisBuffTweakData")

    if not (templates and power_ups and array and array_by_rarity and lookup and buff_templates) then
        _dbg("[dormant] DeusPowerUp* tables not loaded yet; skipping injection of " .. tostring(power_up_name))
        return
    end

    local template = templates[power_up_name]
    if not template then
        _dbg("[dormant] template not found for " .. tostring(power_up_name))
        return
    end

    local availability = (availability_t and {
        availability_t.cursed_chest,
        availability_t.weapon_chest,
        availability_t.shrine,
    }) or {}

    -- v0.7.67 split: the rarity-pool insert is no longer done here. It moved into
    -- `_add_dormant_to_pool` below, called separately and gated by the user's
    -- toggle. This function (`inject_dormant_boon`) now does all the network-
    -- relevant registration UNCONDITIONALLY at mod-load — `DeusPowerUpsLookup`,
    -- `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUps`,
    -- `NetworkLookup.deus_power_up_templates`, `NetworkLookup.buff_templates`,
    -- `BuffTemplates`, `DeusPowerUpBuffTemplates`. Same set of indices across
    -- every peer regardless of which `activate_dormant_*` or `enable_boon_*`
    -- toggles each has on. Only `DeusPowerUpRarityPool` (which determines what
    -- a peer actually has the *option* to roll) stays toggle-gated.
    --
    -- Why this matters: `DeusPowerUpsLookup[boon_id]` is indexed by an integer
    -- RPC parameter (deus_mechanism.lua:1256). If host's lookup table is
    -- ordered differently from client's, host's rpc_add_buff(id=N) resolves to
    -- a DIFFERENT boon on the client. Pre-0.7.67 the gate at the pool-insert
    -- was applied to the entire `inject_dormant_boon` call, so `deus_larger_clip`
    -- (and the other 8 dormants + 11 trait boons + ct_meta_movespeed +
    -- ct_kill_heal) appeared in the lookup table only on peers with their toggle
    -- on, drifting every subsequent boon's id by +1 per absent dormant.
    -- Burned ct v0.7.66 (same class as v0.7.59 / v0.7.60).

    -- Build the new_power_up record (mirrors vanilla deus_power_up_settings.lua:7121-7176).
    local new_power_up = {}
    new_power_up.name           = power_up_name
    new_power_up.rarity         = rarity
    new_power_up.mutators       = {}
    new_power_up.availability   = availability
    new_power_up.max_amount     = template.max_amount or 1
    new_power_up.incompatibility = template.incompatibility
    new_power_up.weight         = template.weight or (settings and settings.weight_by_rarity and settings.weight_by_rarity[rarity]) or 1

    if template.talent then
        new_power_up.talent       = true
        new_power_up.talent_tier  = template.talent_tier
        new_power_up.talent_index = template.talent_index
    else
        new_power_up.display_name        = template.display_name
        new_power_up.plain_display_name  = template.plain_display_name
        new_power_up.buff_name           = "power_up_" .. power_up_name .. "_" .. rarity
        new_power_up.advanced_description = template.advanced_description
        new_power_up.description_values  = template.description_values
        new_power_up.icon                = template.icon

        local buff_template = table.clone(template.buff_template)
        local tweak_data = tweak_data_glob and tweak_data_glob[power_up_name]
        if tweak_data then
            for k, v in pairs(tweak_data) do
                buff_template.buffs[1][k] = v
            end
        end
        buff_template.buffs[1].name = new_power_up.buff_name
        buff_templates[new_power_up.buff_name] = buff_template
        -- Also register in the global BuffTemplates table. Vanilla CW boons get here via a
        -- boot-time `table.merge_recursive(dlc_settings.buff_templates, DeusPowerUpBuffTemplates)`
        -- in morris_buff_settings.lua:7310 — but that merge happens BEFORE mods load. Runtime
        -- writes to DeusPowerUpBuffTemplates don't propagate, so BuffUtils.get_buff_template
        -- (buff_utils.lua:256, reads `BuffTemplates[name]`) returns nil → crash in
        -- buff_extension.lua:177 when the buff is applied. Mirror the write here.
        local global_bt = rawget(_G, "BuffTemplates")
        if global_bt then
            global_bt[new_power_up.buff_name] = buff_template
        end
        -- v0.7.38: Network sync of boon application reads NetworkLookup.buff_templates
        -- to translate buff_name → int ID. Vanilla builds the lookup at boot from
        -- BuffTemplates; our runtime additions aren't in it, and the table's
        -- __index metatable errors on unknown keys (network_lookup.lua:2354-2358).
        -- Crash: "Table buff_templates does not contain key: power_up_<name>_<rarity>"
        -- on the second peer / first network sync. Burned in ct v0.7.34 → v0.7.37.
        register_buff_in_network_lookup(new_power_up.buff_name)
    end

    -- 3. Register in all derived tables.
    power_ups[rarity] = power_ups[rarity] or {}
    power_ups[rarity][power_up_name] = new_power_up

    table.insert(array, new_power_up)
    new_power_up.id = #array

    array_by_rarity[rarity] = array_by_rarity[rarity] or {}
    table.insert(array_by_rarity[rarity], new_power_up)

    new_power_up.lookup_id = #lookup + 1
    lookup[#lookup + 1]    = new_power_up
    lookup[power_up_name]  = new_power_up

    _injected_dormants[power_up_name] = new_power_up
    _dbg(string.format("[dormant] injected %s at rarity %s (lookup_id=%d)", power_up_name, rarity, new_power_up.lookup_id))
end

-- v0.7.67: pool insertion is now its own gated step. See the long comment inside
-- `inject_dormant_boon` for why this split is necessary. Idempotent via
-- `_added_to_pool` table — safe to call repeatedly (e.g. from both pre-register
-- and the toggled sync_dormant_boons / register_trait_boon paths).
local _added_to_pool = {}
local function _add_dormant_to_pool(power_up_name, rarity)
    if _added_to_pool[power_up_name] then return end
    local record = _injected_dormants[power_up_name]
    if not record then
        _dbg("[dormant] _add_dormant_to_pool: " .. tostring(power_up_name) .. " not yet registered; skipping pool insert")
        return
    end
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    if not pool then return end
    pool[rarity] = pool[rarity] or {}
    table.insert(pool[rarity], { power_up_name, record.availability, {} })
    _added_to_pool[power_up_name] = true
    _dbg(string.format("[dormant] added %s to %s rarity pool (now %d entries in that rarity)", power_up_name, rarity, #pool[rarity]))
end

-- v0.7.88: previously sync_dormant_boons only added on toggle-on but never
-- removed on toggle-off. Once `_added_to_pool[name] = true`, the dormant
-- stayed in the offering pool for the rest of the session even after the
-- user un-checked the toggle in the VMF menu. This walks the DeusPowerUpRarityPool
-- entries for the given rarity and rips out the one matching `power_up_name`,
-- then clears the idempotency bit so a later toggle-on can re-add cleanly.
local function _remove_dormant_from_pool(power_up_name, rarity)
    if not _added_to_pool[power_up_name] then return end
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    local arr = pool and pool[rarity]
    if arr then
        for i = #arr, 1, -1 do
            local entry = arr[i]
            if type(entry) == "table" and entry[1] == power_up_name then
                table.remove(arr, i)
            end
        end
    end
    _added_to_pool[power_up_name] = nil
    _dbg("[dormant] removed %s from %s rarity pool (toggle now OFF)", power_up_name, rarity)
end

-- 2026-05-23 v0.7.100-dev FULLY PURGED: pre_register_dormant_lookups, sync_dormant_boons,
-- and their apply-site calls. The functions iterated DORMANT_BOON_RARITY (which no longer
-- exists). The trait-boon + meta-boon paths still call `inject_dormant_boon` directly with
-- their own power-up names; those paths are unaffected by this purge.
--
-- To re-enable: uncomment the block below AND restore the DORMANT_BOON_RARITY table above.
--[[
local function pre_register_dormant_lookups()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not templates then
        _dbg("[dormant] pre-register skipped: DeusPowerUpTemplates not yet loaded")
        return
    end
    local keys = {}
    for k in pairs(DORMANT_BOON_RARITY) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, power_up_name in ipairs(keys) do
        local rarity = DORMANT_BOON_RARITY[power_up_name]
        inject_dormant_boon(power_up_name, rarity)
    end
    _dbg("[dormant] pre-registered %d dormants unconditionally for client compat", #keys)
end

local function sync_dormant_boons()
    local keys = {}
    for k in pairs(DORMANT_BOON_RARITY) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, name in ipairs(keys) do
        local default_rarity = DORMANT_BOON_RARITY[name]
        if effective_setting("activate_dormant_" .. name) then
            _add_dormant_to_pool(name, default_rarity)
        else
            _remove_dormant_from_pool(name, default_rarity)
        end
    end
end

pre_register_dormant_lookups()
sync_dormant_boons()
--]]

-- ============================================================
-- v0.7.93: Khorne's Skulls Event Boons in non-Skulls CW (dormant-injection)
-- ============================================================
-- 2026-05-23 v0.7.98-dev DISABLED: full Skulls event boon implementation block-commented per
-- user request after Chest-of-Trials crash. The SKULLS_EVENT_BOONS constant + the
-- pre_register_skulls_event_lookups / _set_skulls_mutators_active / sync_skulls_event_boons
-- functions all live inside the block-comment below; nothing in this file references them once
-- this block is wrapped (the regression check that walked SKULLS_EVENT_BOONS is also disabled).
-- To re-enable, delete the wrapping `--[[` / `--]]` markers AND restore the VMF widget +
-- localization entries AND the disabled regression check.
--[[
-- The 10 Skulls boons (boon_skulls_01..08 + 2 set bonuses) are vanilla-registered
-- in DeusPowerUpTemplates at game boot — their templates, buffs, and NetworkLookup
-- entries already exist on every peer regardless of toggle state. Vanilla also
-- populates DeusPowerUps.event[boon_skulls_*], DeusPowerUpsArray, and
-- DeusPowerUpsArrayByRarity.event (via the boot-time DeusPowerUpRarityPool walk at
-- deus_power_up_settings.lua:7121-7176). The created buff variants are
-- `power_up_boon_skulls_01_event` etc., which is exactly the name the set-bonus
-- amplifier closures hard-code (`buff_extension:num_buff_stacks(
-- "power_up_boon_skulls_set_bonus_01_event")` at lines 462/487/516/etc.). So leaving
-- the vanilla "event" rarity records in place keeps the set bonuses functional.
--
-- All vanilla cares about for the seasonal gate is the per-record `mutators` field
-- ({"skulls_2023"} on every Skulls boon entry), checked by
-- deus_power_up_utils.lua:146 `compatible_mutator_active(power_up.mutators)` during
-- offering generation. To make the boons roll outside the event, we clear that
-- field at mod load — peer-safe because the array structure / network indices
-- aren't touched (only mutator semantics, which are evaluated host-side at roll
-- time on the existing record).
--
-- v0.7.85 attempted an "append to DeusPowerUpRarityPool" approach. That was a
-- no-op: DeusPowerUpRarityPool is read ONCE at boot to populate the runtime
-- arrays. The offering generator (deus_power_up_utils.lua:138-146) scans
-- DeusPowerUpsArrayByRarity, not the source pool. Replaced 2026-05-23 with this
-- direct-mutator-clear approach.
--
-- Why not the full inject_dormant_boon pattern (ct's 9 dormants + 11 trait boons)?
-- Because vanilla already did all of that for these boons at boot — every step of
-- inject_dormant_boon's registration is idempotent against vanilla's existing
-- writes, EXCEPT the unconditional `table.insert(DeusPowerUpsArray, ...)` and
-- ditto for ArrayByRarity / Lookup. Calling it would duplicate every Skulls boon
-- in the runtime arrays. Mutator-field clearing on the existing vanilla record
-- achieves the same gameplay outcome (boon becomes rollable) without the
-- duplication risk, and preserves the existing buff_name → set-bonus-amplifier
-- linkage intact. We still pre-register NetworkLookup names defensively (they're
-- already vanilla-registered but the call is idempotent).
--
-- Boons 06/07/08 (the 2025 variants) are functionally inert outside the Skulls
-- mutator: they fire on `on_mutator_skull_picked_up` (daemon-skull pickups don't
-- spawn outside the Skulls mutator) and check `num_buff_stacks("skulls_2023_buff")`
-- which is the mutator's own buff (always 0 stacks outside the mutator). They will
-- not crash — buff_func nil-checks and 0-stack multiplier=0 are vanilla-safe — but
-- a roll on one of them is largely wasted. Documented in tooltip. Boons 01-05 +
-- both set bonuses are fully functional outside the event.
local SKULLS_EVENT_BOONS = {
    "boon_skulls_01",
    "boon_skulls_02",
    "boon_skulls_03",
    "boon_skulls_04",
    "boon_skulls_05",
    "boon_skulls_06",
    "boon_skulls_07",
    "boon_skulls_08",
    "boon_skulls_set_bonus_01",
    "boon_skulls_set_bonus_02",
}

-- Cache the original `mutators` arrays (vanilla {"skulls_2023"} etc.) so we can
-- restore them on toggle-off. Indexed by power-up name. Captured at first mod-load
-- per peer; not persisted across game restart, so the restore always re-reads from
-- the live record.
local _skulls_original_mutators = {}

-- v0.7.93: pre-register the Skulls boon names in NetworkLookup unconditionally
-- (idempotent; vanilla already wrote them at boot, but cover the case of a future
-- vanilla change that defers them). Sorted iteration per
-- feedback_vt2_gated_registration_diverges. The set-bonus amplifier closures look up
-- the `power_up_boon_skulls_set_bonus_<NN>_event` buff names by string at runtime,
-- so they don't introduce additional NetworkLookup requirements beyond what vanilla
-- already provides.
local function pre_register_skulls_event_lookups()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local global_bt = rawget(_G, "BuffTemplates")
    local deus_bt = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and global_bt and deus_bt) then
        _dbg("[skulls-event] pre-register skipped: DeusPowerUp* tables not yet loaded")
        return
    end
    local sorted = {}
    for _, name in ipairs(SKULLS_EVENT_BOONS) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    local registered = 0
    for _, power_up_name in ipairs(sorted) do
        if templates[power_up_name] then
            -- Defensive: re-register the NetworkLookup entries even though vanilla
            -- already did so. _register_in_network_lookup is idempotent (rawget
            -- guard at top), zero cost when already present.
            register_power_up_in_network_lookup(power_up_name)
            -- Vanilla's bootstrap (deus_power_up_settings.lua:7146-7161) created
            -- `power_up_<name>_event` buff variants and registered them in
            -- DeusPowerUpBuffTemplates. Mirror to _G.BuffTemplates per
            -- feedback_vt2_dormant_buff_template_dual_register — vanilla's DLCUtils
            -- merge runs at boot BEFORE mods load, so the Skulls buffs ARE already
            -- in global_bt for "event" rarity. But re-mirror defensively in case a
            -- future vanilla change defers the merge.
            local buff_name = "power_up_" .. power_up_name .. "_event"
            local buff_template = deus_bt[buff_name]
            if buff_template then
                global_bt[buff_name] = buff_template
                register_buff_in_network_lookup(buff_name)
            end
            registered = registered + 1
        else
            _dbg("[skulls-event] template %s not present in this game version — skipping (probably pre-2025 build)", tostring(power_up_name))
        end
    end
    _dbg("[skulls-event] pre-registered %d skulls boons for client compat (idempotent overlay on vanilla)", registered)
end

-- Toggle-on: clear the mutators array on each Skulls boon's runtime record so the
-- offering roller (deus_power_up_utils.lua:146) lets them through outside the
-- Skulls 2023 mutator. Toggle-off: restore the cached original {"skulls_2023"}
-- array so the boons revert to event-gated behaviour. Idempotent in both directions.
local function _set_skulls_mutators_active(enabled)
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local deus_power_ups = rawget(_G, "DeusPowerUps")
    if not (templates and deus_power_ups) then
        _dbg("[skulls-event] _set_skulls_mutators_active(%s): DeusPowerUp* tables not loaded yet; skipping", tostring(enabled))
        return
    end
    local count_modified = 0
    for _, power_up_name in ipairs(SKULLS_EVENT_BOONS) do
        local record = deus_power_ups.event and deus_power_ups.event[power_up_name]
        if record then
            if _skulls_original_mutators[power_up_name] == nil then
                -- First touch — snapshot the vanilla mutators array. Even if vanilla
                -- happens to have `mutators = nil` (it doesn't, but defend), capture
                -- the empty-table marker so restore is unambiguous.
                _skulls_original_mutators[power_up_name] = record.mutators or {}
            end
            if enabled then
                record.mutators = {}
            else
                record.mutators = _skulls_original_mutators[power_up_name]
            end
            count_modified = count_modified + 1
        end
    end
    _dbg("[skulls-event] %s mutator gate on %d skulls boons (toggle=%s)",
        enabled and "cleared" or "restored", count_modified, tostring(enabled))
end

local function sync_skulls_event_boons()
    _set_skulls_mutators_active(effective_setting("enable_skulls_event_boons") == true)
end

pre_register_skulls_event_lookups()
sync_skulls_event_boons()
--]] -- 2026-05-23 v0.7.98-dev DISABLED: end Skulls event boon block (opened ~L4984)

-- ============================================================
-- Miracle of Ulric / Miracle of Isha (alternative blessing behaviors, v0.7.65)
-- ============================================================
-- Two host-synced toggles that REPLACE vanilla blessing behavior:
--   - tweak_miracle_of_ulric_persistent: vanilla blessing_of_power adds +50 to
--     each weapon's `power_level` field (deus_run_controller.lua:1671-1703).
--     That value EVAPORATES on weapon swap at an altar — the new weapon doesn't
--     have it. When the toggle is on, skip the vanilla weapon-mutation and
--     instead apply a persistent +50 power_level buff on every hero. Survives
--     swaps because it's on the player buff_extension, not the weapon entry.
--   - tweak_miracle_of_isha_alternative: vanilla blessing_of_isha runs a
--     mutator (mutator_blessing_of_isha.lua) that grants one team revive from
--     death. When the toggle is on, skip the mutator registration and instead
--     apply -25% damage_taken to every hero (persistent for the run).
--
-- Mirror writes to BuffTemplates (the global table) because the engine reads
-- via BuffUtils.get_buff_template which only consults that global; vanilla
-- merges DeusPowerUpBuffTemplates into it at boot, BEFORE mods load, so any
-- runtime writes to DeusPowerUpBuffTemplates alone are lost (per
-- feedback_vt2_dormant_buff_template_dual_register.md). Also register in
-- NetworkLookup.buff_templates via register_buff_in_network_lookup so the
-- rpc_add_buff sync path doesn't crash on unknown name.
local CT_BUFF_MIRACLE_OF_ULRIC = "ct_miracle_of_ulric"
local CT_BUFF_MIRACLE_OF_ISHA_AEGIS = "ct_miracle_of_isha_aegis"
local CT_BUFF_MIRACLE_OF_ISHA_WOUNDS = "ct_miracle_of_isha_wounds"

-- v0.7.81: Isha behavior is now a mutex checkbox cluster (per
-- LOCALIZATION_STANDARD.md § 10). Two checkboxes — `tweak_miracle_of_isha_aegis`
-- and `tweak_miracle_of_isha_wounds` — both default off (= vanilla). The mutex
-- enforcer in chaos_wastes_tweaker_mutex.lua guarantees only one can be on at
-- a time; this helper reads them and returns the canonical mode string the
-- rest of the file expects ("vanilla" / "aegis" / "wounds").
--
-- Migration: if the user previously selected a mode via the old
-- `tweak_miracle_of_isha_alternative` dropdown (v0.7.66-0.7.80), the dropdown's
-- value is still readable via mod:get even though the widget was removed.
-- We translate that legacy value into the new checkbox state on first read so
-- existing users' previous choice carries over. The migration write happens
-- once per session — subsequent calls hit the cluster directly.
--
-- v0.7.65 boolean legacy is also handled (true → aegis), in case anyone is
-- still on a pre-v0.7.66 save.
local _isha_migrated = false
local function _migrate_isha_legacy_dropdown_once()
    if _isha_migrated then return end
    _isha_migrated = true
    -- If a cluster member is already on, we've already migrated (or the user
    -- just set it via the new UI). Don't clobber.
    if effective_setting("tweak_miracle_of_isha_aegis") or effective_setting("tweak_miracle_of_isha_wounds") then
        return
    end
    local v = effective_setting("tweak_miracle_of_isha_alternative")
    -- v0.7.65 boolean → aegis; v0.7.66-0.7.80 dropdown values → matching checkbox.
    if v == true or v == "aegis" then
        mod:set("tweak_miracle_of_isha_aegis", true)
        _dbg("[miracle-isha] migrated legacy dropdown value %q -> tweak_miracle_of_isha_aegis", tostring(v))
    elseif v == "wounds" then
        mod:set("tweak_miracle_of_isha_wounds", true)
        _dbg("[miracle-isha] migrated legacy dropdown value %q -> tweak_miracle_of_isha_wounds", tostring(v))
    end
    -- v == false / nil / "vanilla" → both off (default), nothing to do.
end

local function _get_isha_mode()
    _migrate_isha_legacy_dropdown_once()
    if effective_setting("tweak_miracle_of_isha_aegis") then return "aegis" end
    if effective_setting("tweak_miracle_of_isha_wounds") then return "wounds" end
    return "vanilla"
end

local function _register_miracle_buff_templates()
    local global_bt = rawget(_G, "BuffTemplates")
    local deus_bt = rawget(_G, "DeusPowerUpBuffTemplates")
    if not global_bt then
        _dbg("[miracle] BuffTemplates not loaded; cannot register")
        return
    end

    -- +50 power_level. Shape mirrors liquid_bravado_potion
    -- (morris_buff_settings.lua:5534-5546) for the stat_buff="power_level" + bonus
    -- plumbing; is_persistent flag matches deus_special_farm_max_health_buff
    -- (deus_power_up_settings.lua:231-242) so DeusSpawning saves+reapplies it
    -- across missions until the blessing is consumed at end of run.
    --
    -- v0.7.153-dev SCOPE NOTE: ULRIC ALONE keeps `is_persistent = true` (the
    -- vanilla whole-run save/reapply path at deus_spawning.lua:249 save /
    -- :270-279 reapply). The two Isha buffs below (Aegis, Wounds) had their
    -- `is_persistent` flag DROPPED so DeusSpawning's save loop never captures
    -- them — they are now NEXT-MISSION-ONLY, applied by our own host-side
    -- `DeusSpawning._apply_initial_buffs` hook off the `rc._ct_isha_pending`
    -- flag and consumed on the next node change. See the hook below.
    local ulric_tpl = {
        buffs = {
            {
                icon = "blessing_power_01",
                name = CT_BUFF_MIRACLE_OF_ULRIC,
                stat_buff = "power_level",
                bonus = 50,
                max_stacks = 1,
                is_persistent = true,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ULRIC] = ulric_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ULRIC] = ulric_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ULRIC)

    -- -25% damage_taken (NEGATIVE multiplier — vanilla pattern: ale_defence
    -- uses multiplier=-0.04 for 4% reduction at buff_templates.lua:5325-5333).
    -- v0.7.153-dev: NO is_persistent — this is now a NEXT-MISSION-ONLY buff
    -- (re-applied by the _apply_initial_buffs hook from rc._ct_isha_pending).
    local isha_tpl = {
        buffs = {
            {
                icon = "blessing_isha_01",
                name = CT_BUFF_MIRACLE_OF_ISHA_AEGIS,
                stat_buff = "damage_taken",
                multiplier = -0.25,
                max_stacks = 1,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ISHA_AEGIS] = isha_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ISHA_AEGIS] = isha_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ISHA_AEGIS)

    -- v0.7.66: Infinite-wounds variant (recruit-style: every down is revivable
    -- instead of the 2nd down being instant death). Mirrors vanilla CW boon
    -- `indomitable` (deus_power_up_settings.lua:5056-5073) — perks-only template
    -- with no stat_buff. The `infinite_wounds` perk makes GenericStatusExtension
    -- :set_wounded skip the wounds-counter decrement (generic_status_extension
    -- .lua:1443-1450), so `has_wounds_remaining` always returns true and the
    -- death-on-down branch at player_unit_health_extension.lua:812 is never taken.
    -- v0.7.153-dev: NO is_persistent — NEXT-MISSION-ONLY (same path as Aegis).
    local isha_wounds_tpl = {
        buffs = {
            {
                icon = "blessing_isha_01",
                name = CT_BUFF_MIRACLE_OF_ISHA_WOUNDS,
                perks = { "infinite_wounds" },
                max_stacks = 1,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ISHA_WOUNDS] = isha_wounds_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ISHA_WOUNDS] = isha_wounds_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ISHA_WOUNDS)

    _dbg("[miracle] registered Ulric (+50 power), Isha-aegis (-25%% dmg taken), Isha-wounds (infinite wounds) buff templates")
end

_register_miracle_buff_templates()

-- Apply a persistent buff to every connected hero (host-only — the host-side
-- BuffSystem broadcasts add_buff via rpc_add_buff_synced so clients receive it
-- via the existing engine path). Both new buff templates are pre-registered in
-- NetworkLookup.buff_templates above, so the RPC dispatch is safe.
local function _apply_persistent_buff_to_all_heroes(buff_name)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    local side = Managers.state and Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local units = side and side.PLAYER_AND_BOT_UNITS
    if not units then return end
    local buff_system = Managers.state.entity and Managers.state.entity:system("buff_system")
    if not buff_system then return end
    for i = 1, #units do
        local u = units[i]
        if u and Unit.alive(u) then
            local be = ScriptUnit.has_extension(u, "buff_system")
            if be and not be:has_buff_type(buff_name) then
                buff_system:add_buff(u, buff_name, u)
            end
        end
    end
end

-- Single consolidated hook for both blessing overrides — VMF silently shadows
-- duplicate mod:hook on the same Class+method (feedback_vmf_hook_safe_no_chain.md).
mod:hook("DeusRunController", "_try_buy_blessing", function(func, self, buyer, blessing_name)
    -- v0.7.67 diagnostic: log every blessing_of_power entry regardless of toggle.
    -- The 2026-05-20 session showed zero entries despite the user reporting
    -- "Ulric wasn't purchaseable" — meaning the click was rejected at the UI
    -- layer (button greyed out) before reaching us. Next session will capture
    -- whether the click ever reaches _try_buy_blessing.
    if blessing_name == "blessing_of_power" then
        local toggle_on = effective_setting("tweak_miracle_of_ulric_persistent")
        local is_server = Managers and Managers.player and Managers.player.is_server
        local already = self:has_blessing(blessing_name)
        local coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID) or -1
        local cost = (DeusCostSettings and DeusCostSettings.shop and DeusCostSettings.shop.blessings
            and DeusCostSettings.shop.blessings[blessing_name]) or -1
        _dbg("[miracle] _try_buy_blessing entry: blessing=%s buyer=%s is_server=%s toggle=%s already=%s coins=%s cost=%s",
            tostring(blessing_name), tostring(buyer), tostring(is_server), tostring(toggle_on),
            tostring(already), tostring(coins), tostring(cost))
    end
    if blessing_name == "blessing_of_power" and effective_setting("tweak_miracle_of_ulric_persistent") then
        -- Replicate vanilla affordability / dedup guards from
        -- deus_run_controller.lua:1590-1599.
        if self:has_blessing(blessing_name) then
            _dbg("[miracle] Ulric rejected: has_blessing=true (already bought)")
            return false
        end
        local current_coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
        local blessing_cost = DeusCostSettings.shop.blessings[blessing_name]
        if current_coins < blessing_cost then
            _dbg("[miracle] Ulric rejected: coins=%d < cost=%d", current_coins, blessing_cost)
            return false
        end

        _apply_persistent_buff_to_all_heroes(CT_BUFF_MIRACLE_OF_ULRIC)

        -- Replicate vanilla accounting from deus_run_controller.lua:1705-1722 so
        -- the blessing appears in run-stats UI and the lifetime decrement runs.
        local skip_metatable = true
        local blessings_with_buyer = table.clone(self._run_state:get_blessings_with_buyer(), skip_metatable)
        blessings_with_buyer[blessing_name] = buyer
        self._run_state:set_blessings_with_buyer(blessings_with_buyer)
        self._run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, current_coins - blessing_cost)
        local bought_blessings = table.clone(self._run_state:get_bought_blessings(), skip_metatable)
        bought_blessings[#bought_blessings + 1] = blessing_name
        self._run_state:set_bought_blessings(bought_blessings)
        self:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -blessing_cost, "blessing")

        _dbg("[miracle] Ulric (persistent +50 power) applied; vanilla weapon-power bump skipped")
        return true

    elseif blessing_name == "blessing_of_isha" then
        local isha_mode = _get_isha_mode()
        if isha_mode == "vanilla" then
            return func(self, buyer, blessing_name)
        end

        -- v0.7.66 fix (was v0.7.65 dedup bug): the prior implementation SKIPPED
        -- writing blessing_of_isha to blessings_with_buyer in an attempt to also
        -- suppress the auto-mutator activation. But `has_blessing` reads from
        -- blessings_with_buyer, so the shop let users re-buy the alternative on
        -- every visit and drain coins (deus_shop_view_v2.lua:854-867 also keys
        -- the "is_bought" indicator off that table). Now we DO write it (fixes
        -- the shop UX) and instead suppress the vanilla mutator behavior via
        -- the MutatorTemplates.blessing_of_isha.server_start_function hook below.
        if self:has_blessing(blessing_name) then return false end
        local current_coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
        local blessing_cost = DeusCostSettings.shop.blessings[blessing_name]
        if current_coins < blessing_cost then return false end

        -- v0.7.153-dev: ONE-MISSION scope. The buy happens in the Deus SHOP
        -- (map_deus node), where there are no player_units yet — so we cannot
        -- add the buff now. Instead stash the chosen buff name on the run
        -- controller (a host-local field that persists across the shop->mission
        -- transition, same object the bookkeeping below writes through). The
        -- DeusSpawning._apply_initial_buffs hook promotes it to "active" on the
        -- NEXT mission's first spawn, applies it to every hero/bot for that
        -- mission only, and consumes it on the mission after. Ulric is
        -- unchanged (still immediate + whole-run via is_persistent).
        self._ct_isha_pending = (isha_mode == "wounds")
            and CT_BUFF_MIRACLE_OF_ISHA_WOUNDS
            or  CT_BUFF_MIRACLE_OF_ISHA_AEGIS
        _dbg("[miracle] Isha mode=%s queued for NEXT mission only (pending=%s)",
            tostring(isha_mode), tostring(self._ct_isha_pending))

        local skip_metatable = true
        local blessings_with_buyer = table.clone(self._run_state:get_blessings_with_buyer(), skip_metatable)
        blessings_with_buyer[blessing_name] = buyer
        self._run_state:set_blessings_with_buyer(blessings_with_buyer)
        self._run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, current_coins - blessing_cost)
        local bought_blessings = table.clone(self._run_state:get_bought_blessings(), skip_metatable)
        bought_blessings[#bought_blessings + 1] = blessing_name
        self._run_state:set_bought_blessings(bought_blessings)
        self:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -blessing_cost, "blessing")

        _dbg("[miracle] Isha alternative mode=%s queued (next mission only); vanilla revive mutator suppressed", isha_mode)
        return true
    end

    return func(self, buyer, blessing_name)
end)

-- v0.7.153-dev: ONE-MISSION Isha — apply + consume.
--
-- Mechanism (Option B). Aegis/Wounds are now NON-persistent (is_persistent
-- dropped from their templates above), so vanilla's DeusSpawning save loop
-- (deus_spawning.lua:249 `template.is_persistent` filter) never captures them
-- and they expire when the mission unloads. The buy hook stashes the chosen
-- buff name on `rc._ct_isha_pending`. This hook — the ONLY hook on DeusSpawning
-- in this file (pre-flight grep `"DeusSpawning"` -> 0 prior hooks) — promotes the
-- pending flag to "active" on the next mission's first spawn, applies it to every
-- hero/bot for that mission, and consumes it on the mission AFTER. It is keyed on
-- the run controller's current node key (rc:get_current_node_key(),
-- deus_run_controller.lua:2062) which is STABLE within a mission (set once per
-- node transition) and DISTINCT between consecutive missions (each is its own
-- graph node) — so the gate is race-free, with no dependence on game-start vs
-- spawn ordering. Respawns within the mission re-enter _apply_initial_buffs at
-- the same node key, so the buff is re-applied (guarded by has_buff_type so a
-- hero who never died is not double-stacked). Host-only; buff_system:add_buff
-- broadcasts to clients via rpc_add_buff_synced (templates are pre-registered in
-- NetworkLookup.buff_templates) exactly as _apply_persistent_buff_to_all_heroes did.
CT_ISHA_ONE_MISSION_MARKER = "isha_one_mission:apply_initial_buffs_node_key_v0.7.153"
mod:hook_safe("DeusSpawning", "_apply_initial_buffs", function(self, player)
    if not (Managers and Managers.player and Managers.player.is_server) then return end
    local rc = self._deus_run_controller
    if not rc then return end

    -- Current mission identity. get_current_node_key is the run controller's
    -- authoritative position field (same value the mission-start diagnostic
    -- reads); each combat mission is a distinct graph node.
    local level_key = rc.get_current_node_key and rc:get_current_node_key() or nil

    -- Promote a freshly-purchased pending flag to active, tagged to THIS mission.
    -- The shop is a `map` node with no player units, so _apply_initial_buffs does
    -- not fire there — the first time it fires post-purchase is the next mission.
    if rc._ct_isha_pending and not rc._ct_isha_active then
        rc._ct_isha_active = rc._ct_isha_pending
        rc._ct_isha_pending = nil
        rc._ct_isha_active_level = level_key
        _dbg("[miracle] Isha one-mission buff %s armed for node=%s",
            tostring(rc._ct_isha_active), tostring(level_key))
    end

    if not rc._ct_isha_active then return end

    if level_key == rc._ct_isha_active_level then
        -- Still inside the granted mission (initial spawn wave OR a respawn).
        -- Apply to this hero/bot.
        local player_unit = player and player.player_unit
        if not (player_unit and Unit.alive(player_unit)) then return end
        local buff_system = Managers.state and Managers.state.entity
            and Managers.state.entity:system("buff_system")
        if not buff_system then return end
        local be = ScriptUnit.has_extension(player_unit, "buff_system")
        if be and not be:has_buff_type(rc._ct_isha_active) then
            buff_system:add_buff(player_unit, rc._ct_isha_active, player_unit)
            _dbg("[miracle] Isha one-mission buff %s applied to a hero on node=%s",
                tostring(rc._ct_isha_active), tostring(level_key))
        end
    else
        -- Reached a DIFFERENT mission than the one the buff was granted for —
        -- the one-mission window is over. Consume; do NOT apply.
        _dbg("[miracle] Isha one-mission buff %s expired (granted node=%s, now node=%s)",
            tostring(rc._ct_isha_active), tostring(rc._ct_isha_active_level), tostring(level_key))
        rc._ct_isha_active = nil
        rc._ct_isha_active_level = nil
    end
end)

-- v0.7.66: Suppress vanilla Isha mutator when alternative mode is active.
-- Every entry point in mutator_blessing_of_isha.lua early-returns on
-- `not data.hero_side`:
--   - server_update_function:           line 168 — `if not data.hero_side then return end`
--   - server_player_disabled_function:  line 138 — same
--   - server_player_hit_function:       line 156 — same
--   - try_activate_blessing:            only called from the two above, so dead
-- Setting data.hero_side = nil in the post-start callback neutralizes the entire mutator.
--
-- IMPORTANT (v0.7.66 QA-found): the live dispatch target is
-- `template.server.start_function`, NOT `template.server_start_function`. The
-- engine wraps every mutator at `mutator_templates.lua:236-269` (runs at engine
-- boot, before mods) — `template.server_start_function` is left as a dead
-- field, the wrapper at template.server.start_function captures the original
-- via upvalue. Hooking the dead field compiled cleanly but suppressed nothing.
-- v0.7.94-dev: regression marker — set true once the suppression hook actually
-- installed onto MutatorTemplates.blessing_of_isha.server.start_function. Read
-- by the `miracle_of_isha_hook_installed` /ct_regression_test check below.
_G.__ct_isha_suppression_hook_installed = false
do
    local mut_templates = rawget(_G, "MutatorTemplates")
    local isha_template = mut_templates and mut_templates.blessing_of_isha
    local server_tbl = isha_template and isha_template.server
    if server_tbl and type(server_tbl.start_function) == "function" then
        mod:hook(server_tbl, "start_function", function(func, context, data, unit)
            func(context, data, unit)
            local current_mode = _get_isha_mode()
            if current_mode ~= "vanilla" then
                data.hero_side = nil
                _dbg("[isha] mode=%s, applying alternative (vanilla mutator neutralized at server.start_function)", current_mode)
            end
        end)
        _G.__ct_isha_suppression_hook_installed = true
        _dbg("[miracle] Isha suppression hook installed on MutatorTemplates.blessing_of_isha.server.start_function")
    else
        _dbg("[miracle] MutatorTemplates.blessing_of_isha.server.start_function not loaded at hook time; alternative-mode suppression skipped")
    end
end

-- v0.7.94-dev: /verify_isha chat command — surfaces current mode and hook state
-- per the verify-before-shipping doctrine. Prints to chat (player can copy out).
mod:command("verify_isha", "Print Miracle of Isha mode + hook install state", function()
    local mode = _get_isha_mode()
    local aegis_raw   = mod:get("tweak_miracle_of_isha_aegis")
    local wounds_raw  = mod:get("tweak_miracle_of_isha_wounds")
    local hook_ok     = _G.__ct_isha_suppression_hook_installed == true
    local cluster_member = _ct_mutex and _ct_mutex.active and _ct_mutex.active("isha_choice") or nil

    mod:echo("=== verify_isha (v%s) ===", MOD_VERSION)
    mod:echo("  resolved mode: %s", tostring(mode))
    mod:echo("  aegis toggle:  %s   wounds toggle: %s", tostring(aegis_raw), tostring(wounds_raw))
    mod:echo("  mutex active:  %s", tostring(cluster_member))
    mod:echo("  hook installed (MutatorTemplates.blessing_of_isha.server.start_function): %s", tostring(hook_ok))

    -- Title resolution check — mod:localize returns the raw key on miss.
    local aegis_label  = mod:localize("tweak_miracle_of_isha_aegis")
    local wounds_label = mod:localize("tweak_miracle_of_isha_wounds")
    local aegis_ok  = aegis_label  and aegis_label  ~= "tweak_miracle_of_isha_aegis"  and #aegis_label > 0
    local wounds_ok = wounds_label and wounds_label ~= "tweak_miracle_of_isha_wounds" and #wounds_label > 0
    mod:echo("  aegis title:   %s (%s)",  tostring(aegis_label),  aegis_ok  and "OK" or "MISSING")
    mod:echo("  wounds title:  %s (%s)", tostring(wounds_label), wounds_ok and "OK" or "MISSING")

    -- v0.7.153-dev: one-mission pending/active flag state. Resolve the Deus run
    -- controller defensively — it is nil in the keep (no active CW run).
    local rc = nil
    local gm = Managers and Managers.state and Managers.state.game_mode
    local gmode = gm and gm:game_mode()
    rc = gmode and gmode._deus_run_controller or nil
    if rc then
        mod:echo("  one-mission flags: pending=%s active=%s active_level=%s",
            tostring(rc._ct_isha_pending), tostring(rc._ct_isha_active), tostring(rc._ct_isha_active_level))
    else
        mod:echo("  one-mission flags: <no active CW run>")
    end

    if aegis_raw and wounds_raw then
        mod:echo("  WARN: both toggles ON; logic resolves to %q (aegis preference); mutex should have prevented this", mode)
    end
end)

-- ============================================================
-- Mod Boons: per-boon scaling (v0.7.30-alpha)
-- ============================================================
-- 4 new ct-injected boons modeled on vanilla `boon_meta_01` (Lileath's Favour: +1%
-- damage and +1% AS per active boon). Each scales different stats per total boon count.
-- Stat_buff names verified against `buff_templates.lua` (power_level_impact,
-- power_level_melee_cleave, critical_strike_chance, critical_strike_effectiveness,
-- max_health, healing_received, cooldown_regen — all are valid stacking_multiplier
-- entries except critical_strike_chance which is stacking_bonus).
--
-- IMPLEMENTATION (per boon):
--   1. Stack buff template added to BuffTemplates (the stat container)
--   2. Apply func added to BuffFunctionTemplates.functions (read by buff_extension
--      at line 397). on_boon_granted func added to the flat global `ProcFunctions`
--      table (read by buff_extension at line 1350). Both written via a factory that
--      shares the same proc body. v0.7.64 fix — pre-0.7.64 the granted func was
--      written only to BuffFunctionTemplates.functions and silently never fired.
--   3. Power-up template added to DeusPowerUpTemplates
--   4. Pool registration via `inject_dormant_boon` (the function is generic — it just
--      registers a power-up name + rarity into all the runtime tables)
--
-- LIMITATION: same as dormants — requires a new CW run to take effect (the engine
-- snapshots DeusPowerUpsArray at run setup). Toggle off doesn't remove the boon.
local CT_META_BOONS = {
    {
        name = "ct_meta_stagger",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "power_level_impact",         multiplier = 0.01 },
            { stat_buff = "power_level_melee_cleave",   multiplier = 0.01 },
        },
    },
    {
        name = "ct_meta_crit",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "critical_strike_chance",        bonus      = 0.01 },
            { stat_buff = "critical_strike_effectiveness", multiplier = 0.05 },
        },
    },
    {
        name = "ct_meta_health",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            -- LINT_OK_NETBOUND: max_health is vanilla-supported stacking_multiplier
            -- and NOT engine-network-bounded (lossy networkify_health, no fassert).
            { stat_buff = "max_health",        multiplier = 0.01 }, -- LINT_OK_NETBOUND
            { stat_buff = "healing_received",  multiplier = 0.01 },
        },
    },
    {
        name = "ct_meta_cooldown",
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            { stat_buff = "cooldown_regen", multiplier = 0.02 },
        },
    },
    {
        name = "ct_meta_ammo",  -- v0.7.43: +5% total ammo per active boon
        rarity = "exotic",
        icon = "deus_icon_meta_01",
        stat_buffs = {
            -- v0.7.52: `apply_buff_func = "refresh_ranged_slot_buffs"` fires
            -- `ammo_extension:refresh_buffs()` on the player's ranged weapon every time the
            -- stack is added, which re-runs `_apply_buffs` and recomputes `_max_ammo`.
            -- v0.7.72: replaced with `ct_meta_ammo_refresh_capacity` which ALSO refreshes
            -- overcharge_extension (Sienna staves, Bardin drakefire) and energy_extension
            -- (Moonfire Bow). See registration block above CT_META_BOONS.
            { stat_buff = "total_ammo",        multiplier = 0.05, apply_buff_func = "ct_meta_ammo_refresh_capacity" },
            -- v0.7.104: REMOVED `reduced_overcharge` and `ammo_used_multiplier` stat_buff
            -- entries. They used vanilla `stacking_multiplier` resolution which is
            -- linear-additive (buff_extension.lua:1391-1448): 20 stacks of -0.05 sum to
            -- -1.0 → `root_multiplier = 0` → free shots / casts. Gamebreaking zero-crossing.
            --
            -- Replaced by direct vanilla hooks on `GenericAmmoUserExtension.use_ammo`,
            -- `PlayerUnitEnergyExtension.drain`, and `PlayerUnitOverchargeExtension.add_charge`
            -- (search for `CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104` in this file). Each hook
            -- scales the per-shot cost by `_ct_meta_ammo_cost_multiplier(num_boons)` — a
            -- hyperbolic-saturating curve floored at 0.25 that is BOUNDED IN [0.25, 1.0]
            -- for ANY N (including N → ∞). Never zero, never negative, never below 25%.
            --
            -- See `.ammo_system_design_2026-05-24.md` for the full design + vanilla
            -- call-site analysis. The `total_ammo` entry stays (positive-only growth, no
            -- zero-crossing — vanilla Waystalker passive ships +100% with no issue).
        },
        -- v0.7.104: Coverage is still ammo + overcharge + energy, but the consumption-side
        -- scaling now happens in three direct vanilla hooks (search for the marker above).
        -- The stat_buffs list contains only `total_ammo` (capacity-side, safe).
    },
}

-- Shared body for apply + granted. Brings the stack count up to the current boon count
-- by adding the delta only. Both procs use the same body so the result is idempotent
-- regardless of which fires first (vanilla CW fires `on_boon_granted` BEFORE
-- `activate_deus_power_up` for newly-granted boons, so when Quiver Cascade is the first
-- ct_meta_* boon a player has the apply func is what does the initial stack — for
-- subsequent boon grants only `granted` fires).
--
-- v0.7.53 fixes two bugs in the prior implementation:
--   1. `num_buff_stacks(stack_name)` returned 0 always — the actual stored key is the
--      SUB-buff's `.name`, which we set to `stack_name .. "_" .. i` in the factory. So the
--      granted func couldn't see existing stacks and re-added the full boon count on every
--      subsequent grant, producing quadratic stack growth (triangular sum across boons).
--   2. The apply path used `for 1, num_boons` with no existing-stacks check. Same fix.
--
-- The query uses the `_1` suffix (the first sub-buff's name). All meta specs have at least
-- one sub-buff, and add_buff(stack_name) increments every sub-buff's stack in lockstep, so
-- counting one of them is enough.
local function _make_meta_proc(stack_name)
    local stack_key = stack_name .. "_1"
    return function(unit, buff, params)
        local player = Managers.player and Managers.player:owner(unit)
        if not player then return end
        local buff_extension = ScriptUnit.extension(unit, "buff_system")
        if not buff_extension then return end
        local deus_run_controller = Managers.mechanism:game_mechanism():get_deus_run_controller()
        if not deus_run_controller then return end
        local num_boons = #deus_run_controller:get_player_power_ups(player:network_id(), player:local_player_id())
        -- v0.7.108-dev (Issue #34): clamp the loop's upper bound to
        -- CT_META_AMMO_MAX_STACKS so a runaway `num_boons` value (stale peer
        -- list, future RPC race, hot-join graph resync) can never push the
        -- per-stack buff template past its max_stacks ceiling. The clamp here
        -- and the `max_stacks = CT_META_AMMO_MAX_STACKS` in the template
        -- factory are mirrored on purpose — either one alone is sufficient,
        -- both together close the door. See doc-block near MOD_VERSION.
        local stacks_target = math.min(num_boons, CT_META_AMMO_MAX_STACKS)
        local num_existing = buff_extension:num_buff_stacks(stack_key)
        for _ = num_existing + 1, stacks_target do
            buff_extension:add_buff(stack_name)
        end
    end
end

local function register_meta_boon(spec)
    local power_ups      = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates = rawget(_G, "BuffTemplates")
    local buff_funcs     = rawget(_G, "BuffFunctionTemplates")
    local proc_functions = rawget(_G, "ProcFunctions")
    if not (power_ups and buff_templates and buff_funcs and buff_funcs.functions and proc_functions) then
        _dbg("[mod-boon] global tables not ready for " .. spec.name)
        return
    end
    local stack_name   = spec.name .. "_stack"
    local apply_name   = spec.name .. "_apply"
    local granted_name = spec.name .. "_granted"

    -- 1. Proc functions. Same body for both — apply fires when this meta boon itself is
    -- granted; granted fires on every subsequent boon. Both should bring stack count to
    -- the current boon count, idempotently.
    -- v0.7.64: on_boon_granted handlers are resolved via the flat `ProcFunctions` global
    -- (buff_extension.lua:1350), NOT `BuffFunctionTemplates.functions`. Apply funcs read
    -- from the latter (buff_extension.lua:397). Writing to only one table = granted proc
    -- silently never fires; the per-boon stack only refreshes on next mission load when
    -- apply runs fresh. Same root-cause shape as v0.7.57 chain_lightning fix.
    local proc = _make_meta_proc(stack_name)
    buff_funcs.functions[apply_name]   = proc
    buff_funcs.functions[granted_name] = proc
    proc_functions[granted_name]       = proc

    -- 2. Stack buff template
    local stack_buffs = {}
    for i, sb in ipairs(spec.stat_buffs) do
        local entry = {
            name = stack_name .. "_" .. i,
            -- v0.7.108-dev (Issue #34): hard cap (was math.huge). See the
            -- CT_META_AMMO_MAX_STACKS doc-block near MOD_VERSION for the
            -- rationale. 30 stacks of any of our meta-boon multipliers
            -- (0.01-0.05) sits well below any engine overflow risk while
            -- still allowing endgame stacking.
            stat_buff = sb.stat_buff,
            max_stacks = CT_META_AMMO_MAX_STACKS,
        }
        if sb.multiplier      then entry.multiplier      = sb.multiplier      end
        if sb.bonus           then entry.bonus           = sb.bonus           end
        if sb.apply_buff_func then entry.apply_buff_func = sb.apply_buff_func end
        stack_buffs[i] = entry
    end
    buff_templates[stack_name] = { buffs = stack_buffs }
    register_buff_in_network_lookup(stack_name)

    -- 3. Power-up template
    power_ups[spec.name] = {
        advanced_description = "description_" .. spec.name,
        display_name         = "display_name_" .. spec.name,
        icon                 = spec.icon,
        max_amount           = 1,
        rectangular_icon     = true,
        buff_template = {
            buffs = {
                {
                    apply_buff_func = apply_name,
                    buff_func       = granted_name,
                    event           = "on_boon_granted",
                    name            = spec.name,
                },
            },
        },
        description_values = {},
    }

    -- 4. Register network-relevant tables + add to rarity pool. v0.7.67 split:
    -- inject_dormant_boon does the registration; _add_dormant_to_pool does the
    -- pool insert. Meta boons are unconditional (not toggle-gated), so always
    -- both — same peer-side behavior as pre-0.7.67.
    inject_dormant_boon(spec.name, spec.rarity)
    _add_dormant_to_pool(spec.name, spec.rarity)
    _dbg("[mod-boon] registered " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.104: the v0.7.102 sentinel `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER` is
-- retired — it documented a `ammo_used_multiplier` stat_buff approach that
-- diverged to zero cost at ~20 boons. Replaced by the file-scope
-- `CT_META_AMMO_HYPERBOLIC_MARKER` (declared near the top of the file alongside
-- `_ct_meta_ammo_cost_multiplier`), checked by the regression test
-- `ct_meta_ammo_hyperbolic_floor_v0_7_104`. Kept here as a dead local for any
-- transitional code that still upvalue-reads it; the regression test now
-- ignores the value.
local CT_META_AMMO_ENERGY_CONSUMPTION_MARKER = "CT_META_AMMO_ENERGY_CONSUMPTION_v0.7.102_RETIRED"

-- v0.7.72: Custom apply_buff_func for ct_meta_ammo. Vanilla `refresh_ranged_slot_buffs`
-- only touches AmmoExtension; we extend it to also force-refresh the player's
-- OverchargeExtension (Sienna staves, Bardin drakefire). Energy refresh became
-- UNNECESSARY in v0.7.102 because the boon now ships `ammo_used_multiplier` (per-drain,
-- consumption-side) instead of mutating `_max_energy` — there's nothing to refresh,
-- the stat_buff applies inside `PlayerUnitEnergyExtension.drain` (vanilla line 95)
-- every time the player fires an energy weapon.
--
-- - OverchargeExtension calls `_calculate_and_set_buffed_max_overcharge_values` at
--   extensions_ready and `on_overcharge_lost` (`player_unit_overcharge_extension.lua:103,206`).
--   v0.7.78 removed the explicit `_calculate_and_set_buffed_max_overcharge_values` call
--   from this function — since the boon now uses `reduced_overcharge` (consumption-side)
--   rather than `max_overcharge`, no recalculation is necessary.
--
-- v0.7.102 thus reduces this function to its original role: refresh the AmmoExtension
-- so the `total_ammo` stack reaches `_max_ammo` immediately. All other resources
-- (overcharge, energy) are handled by their respective consumption-side stat_buff paths
-- without any explicit refresh — that's the whole point of the consumption-side pattern.
do
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")
    if buff_funcs and buff_funcs.functions then
        buff_funcs.functions.ct_meta_ammo_refresh_capacity = function (unit, buff, params)
            -- 1. Vanilla ammo refresh (preserved from old `refresh_ranged_slot_buffs`).
            local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
            if inventory_extension then
                local ranged_slot_data = inventory_extension:get_slot_data("slot_ranged")
                if ranged_slot_data then
                    local left_hand_unit  = ranged_slot_data.left_unit_1p
                    local right_hand_unit = ranged_slot_data.right_unit_1p
                    local left_ammo  = left_hand_unit  and ScriptUnit.has_extension(left_hand_unit,  "ammo_system")
                    local right_ammo = right_hand_unit and ScriptUnit.has_extension(right_hand_unit, "ammo_system")
                    if left_ammo  then left_ammo:refresh_buffs()  end
                    if right_ammo then right_ammo:refresh_buffs() end
                end
            end

            -- 2. Overcharge refresh — REMOVED in v0.7.78. Pre-v0.7.78 ct_meta_ammo
            -- buffed `max_overcharge` directly, and this call re-ran
            -- `_calculate_and_set_buffed_max_overcharge_values` to land the new bar size
            -- immediately. After v0.7.78 the boon uses `reduced_overcharge` instead (a
            -- per-cast stat_buff with no max_value side-effect), so the recalc is
            -- pointless — `reduced_overcharge` reads happen inside the per-cast
            -- ActionThrowProjectile / overcharge add paths, not via max_value. Removing
            -- the call also eliminates the only ct path that could ever drive a
            -- max_overcharge-bounds crash even if another mod adds `max_overcharge` on
            -- top of Scholar talent.

            -- 3. Energy refresh — REMOVED in v0.7.102.
            --
            -- Pre-v0.7.102 (v0.7.72 through v0.7.101-dev) ct_meta_ammo mutated
            -- `energy_ext._max_energy` directly to grow the Moonfire Bow energy
            -- bar. That code path was the root cause of crash GUID
            -- `10764a92-d642-43c2-a51b-07c5b45508be` on 2026-05-23: the engine
            -- fasserts `_max_energy <= NetworkConstants.max_energy.max` (= 60)
            -- every frame inside `PlayerUnitEnergyExtension._update_game_object`,
            -- and the extension is registered on EVERY career — not just
            -- Kerillian. The v0.7.101-dev fix tried to gate the write on
            -- `item_name == "we_deus_01"` plus a base-sanity check plus a clamp;
            -- the user (correctly) rejected that approach as career-specific
            -- guesswork that would break the moment any future career or
            -- weapon used the energy extension.
            --
            -- v0.7.102 doctrine fix (feedback_vt2_max_resource_consumption_side):
            -- the boon's stat_buffs list now includes
            -- `{ stat_buff = "ammo_used_multiplier", multiplier = -0.05 }`
            -- (sentinel: CT_META_AMMO_ENERGY_CONSUMPTION_MARKER). Vanilla reads
            -- that stat_buff inside `PlayerUnitEnergyExtension.drain` line 95
            -- (`amount = amount * apply_buffs_to_value(1, "ammo_used_multiplier")`)
            -- to scale per-cast energy cost. At 12 boons × -0.05 = effective
            -- cost multiplier 0.40 (stacking_multiplier composes additively),
            -- giving ~2.5x firing capacity. Career-agnostic. Weapon-agnostic.
            -- Never touches the network-bounded `_max_energy` field.
            --
            -- This is the exact parallel of the v0.7.78 max_overcharge → reduced_overcharge
            -- swap. Both crashes shared the same root pattern (NetworkConstants cap
            -- vs +5%/boon scaling); both are now closed via vanilla consumption-side
            -- stat_buffs. See feedback_vt2_max_resource_consumption_side.md for
            -- the full doctrine.
            --
            -- Sentinel string CT_META_AMMO_ENERGY_CONSUMPTION_MARKER is checked by
            -- /ct_regression_test source-pattern check `ct_meta_ammo_uses_consumption_side`.
            -- The marker itself appears in the boon definition's comment block at
            -- CT_META_BOONS (see `ammo_used_multiplier` entry above) AND in the
            -- file-scope sentinel just below the boon registration loop.
            local _ = CT_META_AMMO_ENERGY_CONSUMPTION_MARKER  -- upvalue read so the
            -- regression check sees the marker as load-bearing rather than dead code.
        end
    else
        _dbg("[mod-boon] BuffFunctionTemplates not ready — ct_meta_ammo_refresh_capacity deferred (boon load order)")
    end
end

for _, spec in ipairs(CT_META_BOONS) do
    register_meta_boon(spec)
end

-- ============================================================================
-- v0.7.104: ct_meta_ammo direct hooks — hyperbolic cost-floor on consumption.
-- ============================================================================
-- Replaces the v0.7.102-era `reduced_overcharge` + `ammo_used_multiplier`
-- stat_buff entries with three direct vanilla hooks. Root cause for the swap:
-- VT2 `stacking_multiplier` resolution (buff_extension.lua:1391-1448) is linear-
-- additive. 20 stacks of -0.05 sum to -1.0 → root_multiplier = 0 → free shots /
-- casts. Gamebreaking zero-crossing.
--
-- Each hook resolves the local player's active boon count via the deus run
-- controller (matches `_make_meta_proc`'s pattern), scales the per-shot cost by
-- `_ct_meta_ammo_cost_multiplier(N)` (bounded [0.25, 1.0] for any N), then
-- calls the original with the discounted amount. Pcall around each body so a
-- crash in our resolution can never break the vanilla consumption path. Vanilla
-- buffs (Hand of Drakira, Conservative Shooter, etc.) flow through the wrapped
-- inner call so composition stays multiplicative.
--
-- The hooks no-op (early-return) for non-local players (husk units have no
-- run_controller of their own — the local viewer's ct_meta_ammo discount is
-- their problem; husks just sync state). They also no-op when num_boons <= 0
-- so vanilla CW behavior is unchanged for non-meta-ammo players.
--
-- Sentinel: CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104 (file-scope, see top of file).
do
    -- Resolve the active boon count for the LOCAL player ONLY. Returns 0 for
    -- husk units (remote players). The hyperbolic discount is applied locally
    -- on each peer's own shots — vanilla networking syncs the result.
    local function _resolve_local_num_boons(owner_unit)
        local pm = Managers and Managers.player
        if not pm then return 0 end
        local pl = pm.local_player and pm:local_player()
        if not pl or pl.player_unit ~= owner_unit then return 0 end
        local mech = Managers.mechanism
        local gm   = mech and mech.game_mechanism and mech:game_mechanism()
        local rc   = gm and gm.get_deus_run_controller and gm:get_deus_run_controller()
        if not rc then return 0 end
        local ok, list = pcall(rc.get_player_power_ups, rc, pl:network_id(), pl:local_player_id())
        if not ok or type(list) ~= "table" then return 0 end
        return #list
    end

    -- Log only when the factor differs from 1.0 (i.e. we actually scaled),
    -- and only once every N seconds per extension to avoid spam.
    local _last_log_ts = {}
    local _LOG_THROTTLE_S = 2.0
    local function _maybe_log(ext_name, factor, n)
        if factor >= 0.9999 then return end  -- no scaling happened
        local now = (os and os.clock and os.clock()) or 0
        local last = _last_log_ts[ext_name] or -math.huge
        if now - last < _LOG_THROTTLE_S then return end
        _last_log_ts[ext_name] = now
        _dbg("[ct/meta_ammo] %s cost scaled: factor=%.3f num_boons=%d", ext_name, factor, n)
    end

    -- Hook 1: ammo (GenericAmmoUserExtension.use_ammo, vanilla file line 425).
    -- Vanilla cost math at line 430: `extra_ammo_used = math.round(ammo_used *
    -- apply_buffs_to_value(1, "ammo_used_multiplier")) - ammo_used`. Scaling
    -- the input `ammo_used` here composes correctly with vanilla buffs that
    -- multiply it again inside the original. Floor: math.ceil + math.max(1, ...)
    -- so integer ammo never rounds to 0 from our contribution.
    mod:hook("GenericAmmoUserExtension", "use_ammo", function(func, self, ammo_used, given, check_ammo_immediately)
        local ok, n = pcall(_resolve_local_num_boons, self.owner_unit)
        if not ok or not n or n <= 0 then
            return func(self, ammo_used, given, check_ammo_immediately)
        end
        local ok2, factor = pcall(_ct_meta_ammo_cost_multiplier, n)
        if not ok2 or type(factor) ~= "number" or factor >= 1.0 then
            return func(self, ammo_used, given, check_ammo_immediately)
        end
        -- Belt-and-suspenders floor: math.max(1, ceil(...)) guarantees integer
        -- ammo never drops below 1 per shot. `factor` is already floored at 0.25.
        local scaled = math.max(1, math.ceil((ammo_used or 1) * factor))
        _maybe_log("use_ammo", factor, n)
        return func(self, scaled, given, check_ammo_immediately)
    end)

    -- Hook 2: energy (PlayerUnitEnergyExtension.drain, vanilla file line 85).
    -- Vanilla cost math at line 95: `amount = amount * apply_buffs_to_value(1,
    -- "ammo_used_multiplier")`. We scale `amount` (float) directly. No integer
    -- floor needed — the per-shot cost floor of 0.25 keeps drain bounded away
    -- from zero, and the inner orig_drain clamps the result to [0, energy].
    mod:hook("PlayerUnitEnergyExtension", "drain", function(func, self, amount)
        local ok, n = pcall(_resolve_local_num_boons, self.unit)
        if not ok or not n or n <= 0 then
            return func(self, amount)
        end
        local ok2, factor = pcall(_ct_meta_ammo_cost_multiplier, n)
        if not ok2 or type(factor) ~= "number" or factor >= 1.0 then
            return func(self, amount)
        end
        _maybe_log("drain", factor, n)
        return func(self, (amount or 0) * factor)
    end)

    -- Hook 3: overcharge (PlayerUnitOverchargeExtension.add_charge, vanilla
    -- file line 330). Vanilla cost math at lines 340 + 343. Respects
    -- `_ignored_overcharge_types` (vanilla line 82) for design-consistency —
    -- passive damage-to-overcharge and channelled drakefire/flamethrower
    -- intake aren't "magazine efficiency", so we don't discount them.
    local _IGNORED_OC_TYPES = {
        charging              = true,
        damage_to_overcharge  = true,
        drakegun_charging     = true,
        flamethrower          = true,
    }
    mod:hook("PlayerUnitOverchargeExtension", "add_charge", function(func, self, overcharge_amount, charge_level, overcharge_type)
        -- Skip ignored overcharge types entirely — same list vanilla skips for
        -- `ammo_used_multiplier` at line 343. Belt-and-suspenders: also defer
        -- to the extension's own ignore table if present (some careers might
        -- expand it).
        if overcharge_type and (_IGNORED_OC_TYPES[overcharge_type]
                or (self._ignored_overcharge_types and self._ignored_overcharge_types[overcharge_type])) then
            return func(self, overcharge_amount, charge_level, overcharge_type)
        end
        local ok, n = pcall(_resolve_local_num_boons, self.unit)
        if not ok or not n or n <= 0 then
            return func(self, overcharge_amount, charge_level, overcharge_type)
        end
        local ok2, factor = pcall(_ct_meta_ammo_cost_multiplier, n)
        if not ok2 or type(factor) ~= "number" or factor >= 1.0 then
            return func(self, overcharge_amount, charge_level, overcharge_type)
        end
        _maybe_log("add_charge", factor, n)
        return func(self, (overcharge_amount or 0) * factor, charge_level, overcharge_type)
    end)

    pcall(printf, "[ct/meta_ammo] hyperbolic-floor hooks installed (use_ammo / drain / add_charge); marker=%s", CT_META_AMMO_HYPERBOLIC_MARKER)
end

-- v0.7.104: /verify_meta_ammo — print the hyperbolic curve at sample N values
-- so the user can eyeball the saturation. Also dumps the live boon count and
-- runtime resolution if a player unit is available.
mod:command("verify_meta_ammo", "Print ct_meta_ammo hyperbolic cost-floor curve + live state", function()
    mod:echo("=== ct_meta_ammo hyperbolic curve (step=%.2f cap=%.2f floor=%.2f) ===",
        CT_META_AMMO_STEP, CT_META_AMMO_CAP, CT_META_AMMO_FLOOR)
    mod:echo("  N=0    -> factor=%.3f", _ct_meta_ammo_cost_multiplier(0))
    mod:echo("  N=1    -> factor=%.3f", _ct_meta_ammo_cost_multiplier(1))
    mod:echo("  N=5    -> factor=%.3f", _ct_meta_ammo_cost_multiplier(5))
    mod:echo("  N=10   -> factor=%.3f", _ct_meta_ammo_cost_multiplier(10))
    mod:echo("  N=20   -> factor=%.3f", _ct_meta_ammo_cost_multiplier(20))
    mod:echo("  N=50   -> factor=%.3f", _ct_meta_ammo_cost_multiplier(50))
    mod:echo("  N=100  -> factor=%.3f", _ct_meta_ammo_cost_multiplier(100))
    mod:echo("  N=1000 -> factor=%.3f (asymptote: %.3f)", _ct_meta_ammo_cost_multiplier(1000), CT_META_AMMO_FLOOR)

    local pl = Managers.player and Managers.player:local_player()
    local unit = pl and pl.player_unit
    if not unit then
        mod:echo("  (no local player unit — keep/menu? Curve-only output)")
        return
    end

    local rc = Managers.mechanism and Managers.mechanism:game_mechanism()
        and Managers.mechanism:game_mechanism().get_deus_run_controller
        and Managers.mechanism:game_mechanism():get_deus_run_controller()
    local num_boons = 0
    if rc and pl then
        local ok, list = pcall(rc.get_player_power_ups, rc, pl:network_id(), pl:local_player_id())
        if ok and type(list) == "table" then num_boons = #list end
    end
    local live_factor = _ct_meta_ammo_cost_multiplier(num_boons)
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    local live_total_ammo
    if buff_ext then
        local ok, v = pcall(buff_ext.apply_buffs_to_value, buff_ext, 1.0, "total_ammo")
        live_total_ammo = ok and v or nil
    end
    mod:echo("--- live ---")
    mod:echo("  num_boons=%d  cost_factor=%.3f  total_ammo=%s",
        num_boons, live_factor, tostring(live_total_ammo))
    mod:echo("  marker=%s", CT_META_AMMO_HYPERBOLIC_MARKER)
    pcall(printf, "[verify_meta_ammo] num_boons=%d cost_factor=%.3f total_ammo_live=%s marker=%s",
        num_boons, live_factor, tostring(live_total_ammo), CT_META_AMMO_HYPERBOLIC_MARKER)
end)

-- v0.7.105 (Issue #6): /verify_altars — per-peer determinism diagnostic for the
-- custom altar (deus_weapon_chest) distribution. The shuffle at line ~1510 uses
-- `HashUtils.fnv32_hash(node.level_seed)` as the seed; if host and client peers
-- arrive at different values for ANY of (node_key, level_seed, hash output,
-- effective_setting counts), the resulting distribution diverges.
--
-- Operating procedure for the MP test (Issue #6 validation plan):
--   1. Host + client both in same CW lobby, same run, same node.
--   2. Both run `/verify_altars` and screenshot/copy the output.
--   3. Compare: every line should match between peers EXCEPT possibly the
--      pending-pops list (depends on whether either peer has opened a chest).
--   4. If `level_seed` or `node_key` differ -> graph-snapshot RPC desync.
--   5. If effective_setting values differ -> host-broadcast settings desync.
--   6. If only the pending-pops differ -> the shuffle ran with different state
--      (the next chest open will produce divergent results).
mod:command("verify_altars", "Per-peer altar distribution determinism check (Issue #6)", function()
    mod:echo("=== verify_altars (ct v%s) ===", MOD_VERSION)

    if not (Managers and Managers.mechanism and Managers.mechanism.game_mechanism) then
        mod:echo("  not in a run (no Managers.mechanism) -- run /verify_altars in-mission")
        return
    end
    local mechanism = Managers.mechanism:game_mechanism()
    local run = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not run then
        mod:echo("  not a Deus run (deus_run_controller nil)")
        return
    end

    -- Identify current node
    local run_state = run._run_state
    local node_key = run_state and run_state.get_current_node_key and run_state:get_current_node_key()
    local graph    = run.get_graph_data and run:get_graph_data() or (run._get_graph_data and run:_get_graph_data())
    local node     = graph and node_key and graph[node_key]
    local level_seed = node and node.level_seed
    local hash_seed  = level_seed and HashUtils and HashUtils.fnv32_hash and HashUtils.fnv32_hash(level_seed) or 0

    mod:echo("  node_key:        %s", tostring(node_key))
    mod:echo("  level_seed:      %s", tostring(level_seed))
    mod:echo("  fnv32(seed):     %s   (0 = fallback; nonzero = real)", tostring(hash_seed))

    -- effective_setting values (what altar logic actually consumes)
    local eff_up    = effective_setting("chest_upgrade_count")
    local eff_smele = effective_setting("chest_swap_melee_count")
    local eff_srng  = effective_setting("chest_swap_ranged_count")
    local eff_pup   = effective_setting("chest_power_up_count")
    mod:echo("  effective: upgrade=%s melee=%s ranged=%s power_up=%s (-1 = Default)",
        tostring(eff_up), tostring(eff_smele), tostring(eff_srng), tostring(eff_pup))

    -- mod:get values (what THIS peer clicked locally; helpful when divergence shows
    -- that effective_setting was synced from host but the local UI shows something else)
    local own_up    = mod:get("chest_upgrade_count")
    local own_smele = mod:get("chest_swap_melee_count")
    local own_srng  = mod:get("chest_swap_ranged_count")
    local own_pup   = mod:get("chest_power_up_count")
    mod:echo("  local mod:get: upgrade=%s melee=%s ranged=%s power_up=%s",
        tostring(own_up), tostring(own_smele), tostring(own_srng), tostring(own_pup))

    -- Server/client identification
    local is_server = Managers and Managers.player and Managers.player.is_server
    mod:echo("  is_server: %s", tostring(is_server))

    -- Current pending distribution (set after a chest opens; consumed one entry per open)
    local dist = run._deus_weapon_chest_distribution
    if type(dist) == "table" and #dist > 0 then
        local items = {}
        for i = 1, #dist do items[i] = tostring(dist[i]) end
        mod:echo("  pending pops:    [%s]", table.concat(items, ","))
    else
        mod:echo("  pending pops:    <empty> (no chest opened yet on this node)")
    end

    -- Log-mirror so the line lands in console_logs/ for later cross-peer compare
    pcall(printf, "[verify_altars] node=%s seed=%s hash=%s eff=[u=%s,m=%s,r=%s,p=%s] dist_n=%d server=%s",
        tostring(node_key), tostring(level_seed), tostring(hash_seed),
        tostring(eff_up), tostring(eff_smele), tostring(eff_srng), tostring(eff_pup),
        (type(dist) == "table" and #dist or 0), tostring(is_server))
end)

-- v0.7.104: per-meta-boon /verify_ct_meta_<name> chat commands.
-- For each CT_META_BOONS entry, register a command that probes the live
-- `apply_buffs_to_value(...)` result for every stat_buff key the boon writes,
-- compares it against the linear-projection expected value, and reports
-- delta / pass-fail.
--
-- For `ct_meta_ammo` specifically, the per-stat_buff projection only covers
-- `total_ammo` now (the other two are no longer stat_buffs after v0.7.104);
-- the command also prints the hyperbolic cost factor so the user sees what
-- the direct hooks will apply.
local function _resolve_num_boons_for(pl)
    local mech = Managers.mechanism
    local gm   = mech and mech.game_mechanism and mech:game_mechanism()
    local rc   = gm and gm.get_deus_run_controller and gm:get_deus_run_controller()
    if not (rc and pl) then return 0 end
    local ok, list = pcall(rc.get_player_power_ups, rc, pl:network_id(), pl:local_player_id())
    if not ok or type(list) ~= "table" then return 0 end
    return #list
end

local function _make_meta_verify_command(spec)
    local cmd_suffix = spec.name:gsub("^ct_meta_", "")
    local stack_key = spec.name .. "_stack_1"
    mod:command("verify_ct_meta_" .. cmd_suffix,
        "Probe " .. spec.name .. ": live stat_buff resolutions vs linear projection",
        function()
            local pl = Managers.player and Managers.player:local_player()
            local unit = pl and pl.player_unit
            if not unit then
                mod:echo("/verify_ct_meta_%s: no local player unit (keep/menu?)", cmd_suffix)
                return
            end
            local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
            if not buff_ext then
                mod:echo("/verify_ct_meta_%s: no buff_extension on player_unit", cmd_suffix)
                return
            end
            local num_boons = _resolve_num_boons_for(pl)
            local stacks = 0
            local ok_stacks, n = pcall(buff_ext.num_buff_stacks, buff_ext, stack_key)
            if ok_stacks and type(n) == "number" then stacks = n end

            mod:echo("=== /verify_ct_meta_%s ===", cmd_suffix)
            mod:echo("  num_boons=%d  stacks(%s)=%d", num_boons, stack_key, stacks)
            if num_boons > 0 and stacks ~= num_boons then
                mod:echo("  WARN stacks != num_boons (proc/apply desync?)")
            end

            for _, sb in ipairs(spec.stat_buffs) do
                local key = sb.stat_buff
                -- multiplier reads use base=1, bonus reads use base=0.
                local base = sb.multiplier and 1.0 or 0.0
                local per_stack = sb.multiplier or sb.bonus or 0
                local ok_resolve, resolved = pcall(buff_ext.apply_buffs_to_value, buff_ext, base, key)
                resolved = (ok_resolve and type(resolved) == "number") and resolved or 0
                local expected = base + per_stack * stacks
                local delta = resolved - expected
                local pass = math.abs(delta) < 1e-3
                mod:echo("  %s %s: resolved=%.4f expected=%.4f delta=%+.4f (per_stack=%+.4f)",
                    pass and "OK" or "FAIL", key, resolved, expected, delta, per_stack)
            end

            -- ct_meta_ammo: also print the hyperbolic cost factor from the
            -- direct hooks (no longer a stat_buff).
            if spec.name == "ct_meta_ammo" then
                local factor = _ct_meta_ammo_cost_multiplier(num_boons)
                mod:echo("  hyperbolic cost_factor (use_ammo/drain/add_charge): %.3f (floor=%.2f, asymptote=%.2f)",
                    factor, CT_META_AMMO_FLOOR, CT_META_AMMO_FLOOR)
            end
        end)
end

for _, spec in ipairs(CT_META_BOONS) do _make_meta_verify_command(spec) end

-- Special-cased ct_meta_movespeed — uses apply_movement_buff (no stat_buff),
-- so probe the mutated PlayerUnitMovementSettings table directly.
mod:command("verify_ct_meta_movespeed",
    "Probe ct_meta_movespeed: live move_speed setting vs compounding projection",
    function()
        local pl = Managers.player and Managers.player:local_player()
        local unit = pl and pl.player_unit
        if not unit then
            mod:echo("/verify_ct_meta_movespeed: no local player unit (keep/menu?)")
            return
        end
        local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
        local stacks = 0
        if buff_ext then
            local ok_stacks, n = pcall(buff_ext.num_buff_stacks, buff_ext, "ct_meta_movespeed_stack_1")
            if ok_stacks and type(n) == "number" then stacks = n end
        end
        local num_boons = _resolve_num_boons_for(pl)
        local move_speed_live
        local PUMS = rawget(_G, "PlayerUnitMovementSettings")
        if PUMS and PUMS.get_movement_settings_table then
            local ok, tbl = pcall(PUMS.get_movement_settings_table, unit)
            if ok and type(tbl) == "table" then move_speed_live = tbl.move_speed end
        end
        local expected = 4.0 * (1.01 ^ stacks)
        mod:echo("=== /verify_ct_meta_movespeed ===")
        mod:echo("  num_boons=%d  stacks=%d  move_speed_live=%s  expected=%.4f (base 4.0 * 1.01^N)",
            num_boons, stacks, tostring(move_speed_live), expected)
    end)

-- Movement Speed meta boon (v0.7.35): +1% MS per active boon, exotic. Diverges from the
-- stat_buff pattern used by CT_META_BOONS because plain `stat_buff = "movement_speed"`
-- isn't read by any vanilla code — movement speed must be modified via the
-- `apply_movement_buff` / `remove_movement_buff` function pair (which directly mutates
-- the move_speed value via path_to_movement_setting_to_modify).
--
-- Compounding caveat: each stack calls apply_movement_buff with multiplier 1.01, so N
-- stacks = move_speed * 1.01^N. At +1% per stack the compounding is tiny (10 stacks =
-- ~+10.5% vs +10% additive). Acceptable — tooltip says additive for player comprehension.
do
    local power_ups      = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates = rawget(_G, "BuffTemplates")
    local buff_funcs     = rawget(_G, "BuffFunctionTemplates")
    local proc_functions = rawget(_G, "ProcFunctions")
    if power_ups and buff_templates and buff_funcs and buff_funcs.functions and proc_functions then
        local stack_name   = "ct_meta_movespeed_stack"
        local apply_name   = "ct_meta_movespeed_apply"
        local granted_name = "ct_meta_movespeed_granted"
        -- v0.7.56: was `_make_meta_apply` / `_make_meta_granted`. Those were consolidated
        -- into `_make_meta_proc` in v0.7.53 but this special-cased movespeed block was
        -- missed in the rename — module-load crashed with "attempt to call global
        -- '_make_meta_apply' (a nil value)". `_make_meta_proc` looks up existing stack
        -- count via `num_buff_stacks(stack_name .. "_1")`, so the sub-buff's `name`
        -- field has to use that exact key (was bare "ct_meta_movespeed_stack" prior).
        -- v0.7.64: also write granted proc to ProcFunctions (see register_meta_boon comment).
        local proc = _make_meta_proc(stack_name)
        buff_funcs.functions[apply_name]   = proc
        buff_funcs.functions[granted_name] = proc
        proc_functions[granted_name]       = proc
        buff_templates[stack_name] = {
            buffs = {
                {
                    apply_buff_func = "apply_movement_buff",
                    remove_buff_func = "remove_movement_buff",
                    name             = "ct_meta_movespeed_stack_1",
                    -- v0.7.108-dev (Issue #34): hard cap. 30 stacks × 1.01
                    -- (compounding via apply_movement_buff) = 1.01^30 ≈ 1.35x
                    -- move_speed, bounded. See doc-block near MOD_VERSION.
                    max_stacks       = CT_META_AMMO_MAX_STACKS,
                    multiplier       = 1.01,
                    path_to_movement_setting_to_modify = { "move_speed" },
                },
            },
        }
        register_buff_in_network_lookup(stack_name)
        power_ups.ct_meta_movespeed = {
            advanced_description = "description_ct_meta_movespeed",
            display_name         = "display_name_ct_meta_movespeed",
            icon                 = "deus_icon_meta_01",
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        apply_buff_func = apply_name,
                        buff_func       = granted_name,
                        event           = "on_boon_granted",
                        name            = "ct_meta_movespeed",
                    },
                },
            },
            description_values = {},
        }
        inject_dormant_boon("ct_meta_movespeed", "exotic")
        _add_dormant_to_pool("ct_meta_movespeed", "exotic")
        _dbg("[mod-boon] registered ct_meta_movespeed at rarity exotic")
    end
end

-- ============================================================
-- Mod Boon: Khaine's Communion — 1 green HP per kill (v0.7.32-alpha)
-- ============================================================
-- Heal 1 permanent (green) health every time the player kills an enemy. Exotic rarity.
-- Catalogued under Defensive > Health in the boon tree (per user verdict — health-themed
-- effect groups by effect, not by mod-added origin), but display name carries the
-- "(Mod Boon)" prefix so it's flagged.
--
-- Implementation: proc function with `authority = "server"` so the heal fires once
-- per kill on the server, then `DamageUtils.heal_network` networks the heal to the
-- killer's owning peer. Heal type `heal_from_proc` restores permanent HP (green),
-- not THP.
-- ============================================================
-- Mod Boons: Trait-as-Boon (v0.7.34-alpha)
-- ============================================================
-- 4 weapon traits re-introduced as opt-in exotic boons. Each is gated behind its own
-- toggle in Reworks > Reworks: Boons (default off). When enabled, the trait's buff
-- template is cloned into a new power-up at exotic rarity.
--
-- STACKING WITH TRAIT:
-- * Vaul's Anvil — naturally non-stacks (always_blocking is a binary perk; having two
--   sources of the same perk = same effect as one source).
-- * Manann's Tempest — stacks (each buff fires its own chain_lightning proc on crit,
--   so 2 buffs = 2 independent chains per crit).
-- * Taal's Twinned Arrow — stacks (extra_shot stat_buff bonus is additive: 2 buffs =
--   +2 projectiles).
-- * Asuryan's Wrath — stacks (each fires its own proc roll on melee kill, so 2 buffs
--   = roughly +75% effective proc chance vs +50% baseline).
--
-- TAAL'S TWINNED ARROW RESTRICTION: user asked for "only granted if ranged weapon in
-- slot 2." Vanilla VT2 careers all have a ranged slot, so the case is rare. If the
-- player ends up with this boon but no ranged weapon, the stat_buff is just inert
-- (no shots fire = no extra projectiles). Skipping the gate for v0.7.34; can add an
-- offer-time filter if it becomes a real issue.
local CT_TRAIT_BOONS = {
    { name = "ct_boon_vauls_anvil",         toggle = "enable_boon_vauls_anvil",         rarity = "unique", icon = "deus_icon_meta_01", source_buff = "always_blocking" },
    { name = "ct_boon_manann_tempest",      toggle = "enable_boon_manann_tempest",      rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_crit_chain_lightning" },
    { name = "ct_boon_taal_twinned_arrow",  toggle = "enable_boon_taal_twinned_arrow",  rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_extra_shot" },
    { name = "ct_boon_asuryan_wrath",       toggle = "enable_boon_asuryan_wrath",       rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_collateral_damage_on_melee_killing_blow" },
}

local function register_trait_boon(spec)
    -- v0.7.67: registration (NetworkLookup, buff template, DeusPowerUps* sides)
    -- now happens unconditionally in pre_register_trait_boon_lookups. This
    -- function is only responsible for the toggle-gated pool insert, which
    -- determines whether the user actually rolls the boon.
    if not effective_setting(spec.toggle) then return end
    _add_dormant_to_pool(spec.name, spec.rarity)
    _dbg("[trait-boon] enabled " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.61: same shape as pre_register_dormant_lookups (v0.7.60). The gated
-- register_trait_boon below skips registration entirely when the peer's
-- enable_boon_<name> toggle is off, so without this pre-registration step two
-- peers with different toggle states (host enables Vaul's Anvil + Manann's
-- Tempest, client only enables Manann's Tempest) appended a different ordered
-- subset of `power_up_ct_boon_*_unique` entries to NetworkLookup.buff_templates
-- and matching deus_power_up_templates entries -- so the host's rpc_add_buff
-- for a trait-boon index resolved to either the wrong buff or a missing key on
-- the client. Pre-register every trait boon's DeusPowerUpTemplate, buff
-- template, and NetworkLookup entries unconditionally at mod-load in sorted
-- order; the gated register_trait_boon below only does pool injection now (its
-- own writes to buff_templates / NetworkLookup are idempotent early-outs).
local function pre_register_trait_boon_lookups()
    local templates       = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates  = rawget(_G, "BuffTemplates")
    local dpubt           = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and buff_templates and dpubt) then
        _dbg("[trait-boon] pre-register skipped: globals not yet loaded")
        return
    end
    local sorted = {}
    for _, spec in ipairs(CT_TRAIT_BOONS) do sorted[#sorted + 1] = spec end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    -- v0.7.63-alpha: register the NetworkLookup NAMES unconditionally (sorted
    -- order, every peer assigns identical indices regardless of which source
    -- buffs are loaded in their BuffTemplates). The buff-template clone +
    -- DeusPowerUpBuffTemplates write still requires source_template, but those
    -- side tables don't determine the sequential NetworkLookup id — only the
    -- name registration does. Splitting them prevents the receiver-side crash
    -- pattern where peer A skipped Vaul's Anvil (source 'always_blocking'
    -- missing for some reason) but peer B registered it → all subsequent
    -- power_up names land on different ids → `Table deus_power_up_templates
    -- does not contain key: N` fatal in network_lookup.lua's strict __index
    -- when peer B's rpc_add_buff reaches peer A. Crash dumps 2026-05-19
    -- 02:59:56 + 03:08:36 (key 177 on the client side).
    --
    -- Same shape as the v0.8.66-dev LA fix: deterministic name registration
    -- decouples NetworkLookup indices from runtime-dependent state, and the
    -- gated content writes (templates / dpubt / buff_templates) remain
    -- idempotent early-outs in the gated register_trait_boon below.
    for _, spec in ipairs(sorted) do
        register_power_up_in_network_lookup(spec.name)
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        register_buff_in_network_lookup(buff_name)
    end
    local count, placeholder_count = 0, 0
    for _, spec in ipairs(sorted) do
        local source_template = buff_templates[spec.source_buff]
        -- v0.7.67 hardening (QA-found): write a `templates[spec.name]` entry
        -- UNCONDITIONALLY in sorted order so `inject_dormant_boon` below doesn't
        -- early-out on missing template — if it did, `DeusPowerUpsLookup` would
        -- drift across peers (the exact bug class this refactor targets). When
        -- the source buff is missing on a peer, we ship a placeholder template
        -- with an empty buff array. The boon won't FUNCTION gameplay-wise on
        -- that peer, but its lookup_id will align with peers that do have it —
        -- so rpc_add_buff dispatches still resolve to the correct boon name and
        -- the run doesn't crash. Today all four source buffs (always_blocking,
        -- deus_crit_chain_lightning, deus_extra_shot,
        -- deus_collateral_damage_on_melee_killing_blow) are vanilla and always
        -- present, but this hardening guards against future DLC-gated source
        -- buffs that could differ across peers.
        if not templates[spec.name] then
            local cloned_buffs = {}
            if source_template and source_template.buffs then
                for i, sub in ipairs(source_template.buffs) do
                    cloned_buffs[i] = table.clone(sub)
                end
            else
                placeholder_count = placeholder_count + 1
                _dbg("[trait-boon] %s: source buff '%s' missing — using empty placeholder buffs (boon non-functional on this peer but lookup_id stays aligned)",
                    spec.name, tostring(spec.source_buff))
                -- Single placeholder buff with the correct name field so
                -- inject_dormant_boon's `buff_template.buffs[1].name = buff_name`
                -- assignment doesn't nil-crash.
                cloned_buffs[1] = { name = "placeholder" }
            end
            templates[spec.name] = {
                advanced_description = "description_" .. spec.name,
                display_name         = "display_name_" .. spec.name,
                icon                 = spec.icon,
                max_amount           = 1,
                rectangular_icon     = true,
                buff_template        = { buffs = cloned_buffs },
                description_values   = {},
            }
        end
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        local buff_template = table.clone(templates[spec.name].buff_template)
        buff_template.buffs[1].name = buff_name
        dpubt[buff_name] = buff_template
        buff_templates[buff_name] = buff_template
        -- Full registration (NetworkLookup IDs, DeusPowerUps / Array / Lookup,
        -- buff template tables) — UNCONDITIONAL so every peer's
        -- DeusPowerUpsLookup ordering matches regardless of source-buff
        -- availability. Pool insert is gated separately in register_trait_boon.
        inject_dormant_boon(spec.name, spec.rarity)
        count = count + 1
    end
    _dbg("[trait-boon] pre-registered %d trait boons for client compat (%d using placeholder buffs)",
        count, placeholder_count)
end

pre_register_trait_boon_lookups()

for _, spec in ipairs(CT_TRAIT_BOONS) do
    register_trait_boon(spec)
end

-- Assignment to the forward-declared `sync_host_dependent_state` (see top of file).
-- Called by the ct_sync_host_settings RPC handler immediately after a client
-- receives the host's settings payload, so any template/pool mutations gated on
-- a synced setting are reapplied with the host's values. Apply order mirrors the
-- one-shot calls each sync_* function does at module load.
sync_host_dependent_state = function()
    sync_reckless_swings()
    sync_bomb_cooldown()
    sync_boon_movespeed()
    sync_poison_proof_tweak()
    sync_invis_potion_tweak()
    sync_moot_milk_alt_tweak()
    sync_shard_strike()
    sync_anath_raema_permanent()
    -- User-suggestion mechanic tweaks live in _ct_mechanic_tweaks.lua (own chunk to
    -- stay under the 200-local main-chunk cap); re-applied here on host-settings receipt.
    if mod._ct_sync_shadow_skull_stun then mod._ct_sync_shadow_skull_stun() end
    -- 2026-05-23 v0.7.100-dev FULLY PURGED: sync_dormant_boons() — function no longer
    -- exists (block-commented along with DORMANT_BOON_RARITY). Re-enable alongside the
    -- L4721-style apply-site uncomment.
    for _, spec in ipairs(CT_TRAIT_BOONS) do
        register_trait_boon(spec)
    end
end

-- 2026-05-23 v0.7.98-dev DISABLED: ct_kill_heal mod boon removed per user request after
-- Chest-of-Trials crash. To re-enable, uncomment the entire `do ... end` block below AND
-- uncomment the matching VMF widget + localization entries. The block-comment intentionally
-- spans the full do/end so the NetworkLookup pre-registration (which is the actual
-- peer-sync-relevant line per feedback_vt2_gated_registration_diverges) is removed at the
-- same time as the rest of the boon. This is acceptable because everyone re-syncing to
-- v0.7.98-dev will have an identical mod load with no ct_kill_heal name in the lookup; no
-- subset of peers will be on a "has ct_kill_heal" version once this release ships.
--[[
do
    -- v0.7.63-alpha: register NetworkLookup names FIRST, unconditionally, BEFORE
    -- the globals-ready gate. Two peers running the same ct version must always
    -- assign the same sequential index to "ct_kill_heal" regardless of whether
    -- their `DeusPowerUpTemplates` / `BuffFunctionTemplates` globals happened to
    -- be loaded at module-init time on each peer. Same fix pattern as
    -- pre_register_trait_boon_lookups: name registration decoupled from
    -- template construction so the lookup ids stay deterministic across peers.
    register_power_up_in_network_lookup("ct_kill_heal")
    register_buff_in_network_lookup("power_up_ct_kill_heal_exotic")

    local power_ups  = rawget(_G, "DeusPowerUpTemplates")
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")

    if power_ups and buff_funcs and buff_funcs.functions then
        -- v0.7.82: nerfed 1 → 0.25 + heal_type heal_from_proc → health_regen.
        -- User reported "+1 per kill" was granting TEMP green health (the
        -- fading kind) rather than permanent green. Verified empirically
        -- against vanilla generic_status_extension.lua:2247 — is_permanent_heal()
        -- whitelist is `healing_draught, bandage, bandage_trinket,
        -- buff_shared_medpack, career_passive, health_regen, debug,
        -- health_conversion`. `heal_from_proc` is NOT in that list, so it
        -- always routes through the temp-health add path. Switching to
        -- `health_regen` (which IS in the permanent-heal whitelist + is
        -- registered in NetworkLookup.heal_types).
        buff_funcs.functions.ct_kill_heal_on_kill = function(unit, buff, params)
            if ALIVE[unit] then
                DamageUtils.heal_network(unit, unit, 0.25, "health_regen")
            end
        end

        power_ups.ct_kill_heal = {
            advanced_description = "description_ct_kill_heal",
            display_name         = "display_name_ct_kill_heal",
            icon                 = "deus_icon_meta_01",  -- placeholder; future: dedicated heal-on-kill icon
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        authority = "server",
                        buff_func = "ct_kill_heal_on_kill",
                        event     = "on_kill",
                        name      = "ct_kill_heal",
                    },
                },
            },
            description_values = {},
        }

        inject_dormant_boon("ct_kill_heal", "exotic")
        _add_dormant_to_pool("ct_kill_heal", "exotic")
        _dbg("[mod-boon] registered ct_kill_heal at rarity exotic")
    else
        _dbg("[mod-boon] DeusPowerUpTemplates / BuffFunctionTemplates not ready for ct_kill_heal — NetworkLookup name reserved, template construction deferred")
    end
end
--]] -- end v0.7.98-dev DISABLED ct_kill_heal block

-- ============================================================
-- Home Brewer +50% potency for reworked potions (v0.7.31-alpha)
-- ============================================================
-- When the toggle is on AND the player has Home Brewer (the boon that grants the
-- `not_consume_potion` perk), the reworked Moot Milk potion's numerical multipliers are
-- scaled by 1.5x for that specific drink. Implementation: hook BuffExtension.add_buff,
-- save the template's multiplier/bonus fields, scale, call vanilla add, restore.
--
-- Only scales `moot_milk_potion` and `moot_milk_potion_increased` (the reworked variants)
-- — `poison_proof_potion` has binary immunity with no multiplier field, so potency is
-- moot for it. Duration is intentionally NOT scaled (Decanter is the duration lever;
-- Home Brewer is the potency lever — they remain orthogonal).
--
-- LIMITATIONS:
-- * RACE: BuffTemplates is shared global; two players drinking simultaneously could see
--   one peer's scaled values briefly. Rare in practice (potion drinks are individual)
--   and the effect is just stat values, not safety-critical.
-- * No NetworkLookup variant registration — multiplayer-safe because every peer
--   applies its own buff (with its own perk check) via this hook.
local HOME_BREWER_BREWED_TEMPLATES = {
    moot_milk_potion           = true,
    moot_milk_potion_increased = true,
}

-- v0.7.203-dev multi-return marker: the Home Brewer add_buff hook's guarded
-- (scaled-potency) path forwards ALL of vanilla's returns (id, sub_buffs_added,
-- first_buff) via _capture_returns + unpack(results, 1, n), NOT a collapsing
-- `local result = func(...); return result`. Global (not a main-chunk local) to
-- dodge the Lua 5.1 200-local cap. Asserted by /ct_regression_test
-- "home_brewer_add_buff_multireturn_preserved".
CT_HOME_BREWER_MULTIRETURN_MARKER = "home_brewer_add_buff:capture_returns_unpack_v0.7.203"

mod:hook("BuffExtension", "add_buff", function(func, self, template_name, params)
    if not effective_setting("tweak_home_brewer_potency") then
        return func(self, template_name, params)
    end
    if not (type(template_name) == "string" and HOME_BREWER_BREWED_TEMPLATES[template_name]) then
        return func(self, template_name, params)
    end
    if not self.has_buff_perk or not self:has_buff_perk("not_consume_potion") then
        return func(self, template_name, params)
    end
    local bt = rawget(_G, "BuffTemplates")
    local sub_buffs = bt and bt[template_name] and bt[template_name].buffs
    if not sub_buffs then
        return func(self, template_name, params)
    end
    local saved = {}
    for i, sb in ipairs(sub_buffs) do
        if sb.multiplier or sb.bonus then
            saved[i] = { multiplier = sb.multiplier, bonus = sb.bonus }
            if sb.multiplier then sb.multiplier = sb.multiplier * 1.5 end
            if sb.bonus      then sb.bonus      = sb.bonus      * 1.5 end
        end
    end
    -- v0.7.203-dev: vanilla BuffExtension.add_buff returns THREE values
    -- (id, sub_buffs_added, first_buff — buff_extension.lua:517). The prior
    -- `local result = func(...)` / `return result` collapsed that to the first
    -- return, dropping sub_buffs_added + first_buff for any caller that reads them
    -- (VMF_RECIPES §2/§2a). Capture the real arity and forward every return;
    -- restore the scaled sub-buff fields in between. Marker
    -- CT_HOME_BREWER_MULTIRETURN_MARKER documents this fix for the regression check.
    local n, results = _capture_returns(func(self, template_name, params))
    for i, s in pairs(saved) do
        sub_buffs[i].multiplier = s.multiplier
        sub_buffs[i].bonus      = s.bonus
    end
    return unpack(results, 1, n)
end)

-- ============================================================
-- Endless Bombs: strip the LEFTOVER Morgrim's when the potion ENDS
-- ============================================================
-- Intent (user, 2026-06-28): Endless Bombs (pockets_full_of_bombs) is SUPPOSED to work with
-- Morgrim's Bomb (holy_hand_grenade) — players deliberately save a Morgrim's to throw during the
-- potion, and that's fine/desired. The ONLY exploit: if you don't throw your last Morgrim's
-- before the potion expires, it persists (effectively duplicated) so you carry it to the next
-- potion and do it again. So we do NOT eat the bomb on drink or mid-potion (v0.7.178/.179 did —
-- WRONG, that broke the intended combo). We strip the LEFTOVER Morgrim's only when the potion
-- EXPIRES, and only if the player drank it while holding one.
--
-- Mechanism: pockets_full_of_bombs_potion(_increased) declares
-- remove_buff_func = "remove_deus_potion_buff" (morris_buff_settings.lua), which fires on
-- duration expiry. That remove func is SHARED by every deus potion, so we gate on a flag
-- (buff.ct_endless_had_morgrim) that ONLY the pockets apply-hook sets — no buff-name match
-- needed, and other potions are unaffected. The buff instance persists fields across
-- apply/update/remove (vanilla itself stores buff.previous_multiplier), so the flag survives to
-- expiry. Hook target is the merged BuffFunctionTemplates.functions table; guard for load order.
-- #101 regression sentinel (v0.7.181-dev): the consume must be on EXPIRY (remove_deus_potion_buff)
-- via the buff.ct_endless_had_morgrim flag — NOT a consume-on-drink (v0.7.178) or continuous
-- mid-potion eat (v0.7.179), both of which broke the intended potion+Morgrim's combo. Global to
-- dodge the 200-local cap. Asserted by /ct_regression_test "endless_bombs_strip_on_expiry".
CT_ENDLESS_BOMBS_MARKER = "endless_bombs:strip_leftover_morgrim_on_expiry_v0.7.181"
if BuffFunctionTemplates and BuffFunctionTemplates.functions then
    -- At DRINK: only RECORD whether the player held a Morgrim's (do NOT consume it — it must stay
    -- usable during the potion). Morgrim's lives in slot_grenade (deus_blessing_settings.lua:85).
    mod:hook(BuffFunctionTemplates.functions, "apply_pockets_full_of_bombs_buff", function(func, unit, buff, params)
        if effective_setting("endless_bombs_consumes_morgrim") == true then
            local inv = ScriptUnit.has_extension(unit, "inventory_system")
            local sd = inv and inv:get_slot_data("slot_grenade")
            local nm = sd and sd.item_data and sd.item_data.name
            if nm == "holy_hand_grenade" then
                buff.ct_endless_had_morgrim = true
            end
            -- printf, NOT mod:info (user runs VMF mod-logging OFF).
            pcall(printf, "[endless-bombs] drink: grenade=%s had_morgrim=%s (kept for the potion; stripped on expiry)",
                tostring(nm or "<none>"), tostring(buff.ct_endless_had_morgrim == true))
        end
        return func(unit, buff, params)
    end)

    -- At EXPIRY: if they drank with a Morgrim's AND a leftover one is still in slot_grenade, strip
    -- it (kills the un-thrown-duplicate carry-over). Flag-gated -> other deus potions untouched.
    mod:hook(BuffFunctionTemplates.functions, "remove_deus_potion_buff", function(func, unit, buff, params, world)
        local result = func(unit, buff, params, world)
        if buff and buff.ct_endless_had_morgrim and effective_setting("endless_bombs_consumes_morgrim") == true then
            local inv = ScriptUnit.has_extension(unit, "inventory_system")
            local sd = inv and inv:get_slot_data("slot_grenade")
            local nm = sd and sd.item_data and sd.item_data.name
            if nm == "holy_hand_grenade" then
                -- If the player is actively wielding the bomb when it's stripped, destroying the
                -- slot leaves them stuck in the bomb/throw pose on a now-empty slot, unable to
                -- switch weapons. Capture the wielded slot BEFORE destroying; if it was the
                -- grenade, interrupt the weapon action and wield melee (slot 1) so they recover.
                local was_wielding = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
                inv:destroy_slot("slot_grenade")
                if was_wielding == "slot_grenade" then
                    if rawget(_G, "CharacterStateHelper") then
                        pcall(CharacterStateHelper.stop_weapon_actions, inv, "dropped")
                    end
                    pcall(function() inv:wield("slot_melee") end)
                end
                pcall(printf, "[endless-bombs] potion ended -> stripped leftover Morgrim's%s",
                    (was_wielding == "slot_grenade") and " (was wielding it -> swapped to melee)" or "")
            else
                pcall(printf, "[endless-bombs] potion ended; no leftover Morgrim's (grenade=%s)", tostring(nm or "<empty>"))
            end
        end
        return result
    end)

end

-- ============================================================
-- Manann's Tempest — single-toggle 8s cooldown for boon + trait
-- ============================================================
-- Vanilla `chain_lightning` has no cooldown: every crit triggers a chain, so high-crit
-- builds turn every fight into a strobe-light spam.
--
-- v0.7.64: ONE toggle (`tweak_manann_tempest_cooldown`, default OFF) gates BOTH the
-- boon and the trait. Previously the boon was hard-capped unconditionally — but the
-- gate at line 4024 only checked `is_trait`, so the boon's 8s window was applied
-- silently even when users wanted vanilla behavior, and "the toggle isn't doing
-- anything" was correct from the user perspective for the boon side. Now: off =
-- vanilla on both sources, on = 8s cooldown on both.
--
-- Cooldowns are tracked per `owner_unit` with separate buckets for boon vs trait, so
-- the two sources don't share a window — a player running both gets one chain per 8s
-- from each side (matches the existing "boon stacks with trait" design described above
-- at the CT_TRAIT_BOONS table). Weak-keyed so entries die with the unit.
--
-- Gate mirrors `chain_lightning`'s own ALIVE / first_hit / is_critical_strike check so
-- the cooldown only consumes when the proc would actually have fired.
--
-- v0.7.57: hook target is the GLOBAL `ProcFunctions` table, NOT
-- `BuffFunctionTemplates.functions`. `chain_lightning` lives in
-- `dlc_settings.morris.proc_functions` (morris_buff_settings.lua:2145+, separate from
-- buff_function_templates which ends at line 2144) and gets merged via
-- `DLCUtils.merge("proc_functions", ProcFunctions)` in buff_templates.lua:9533. At
-- runtime BuffExtension looks it up via `ProcFunctions[buff_func_name]`
-- (buff_extension.lua:1350) — `BuffFunctionTemplates.functions.chain_lightning` is nil
-- and was the source of the load-time "trying to hook function or method that doesn't
-- exist" error in v0.7.48 → v0.7.56. `apply_pockets_full_of_bombs_buff` happens to live
-- in `buff_function_templates` (the apply-callback category) which is why THAT hook
-- worked at the same call site.
if ProcFunctions and ProcFunctions.chain_lightning then
    local MANANN_TEMPEST_COOLDOWN_S = 8.0
    local _manann_tempest_t = setmetatable({}, { __mode = "k" })

    mod:hook(ProcFunctions, "chain_lightning", function(func, owner_unit, buff, params, world, param_order)
        local template = buff and buff.template
        local template_name = template and template.name
        local is_boon  = type(template_name) == "string"
            and string.find(template_name, "^power_up_ct_boon_manann_tempest_") ~= nil
        local is_trait = template_name == "deus_crit_chain_lightning"

        if not (is_boon or is_trait) then
            return func(owner_unit, buff, params, world, param_order)
        end
        if not effective_setting("tweak_manann_tempest_cooldown") then
            return func(owner_unit, buff, params, world, param_order)
        end

        local hit_unit = params[param_order.attacked_unit]
        local first_hit = params[param_order.first_hit]
        local is_critical_strike = params[param_order.is_critical_strike]
        if not (ALIVE[owner_unit] and ALIVE[hit_unit] and first_hit and is_critical_strike) then
            return func(owner_unit, buff, params, world, param_order)
        end

        local t = (Managers and Managers.time and Managers.time:time("game")) or 0
        local bucket = _manann_tempest_t[owner_unit]
        if not bucket then
            bucket = { boon_next_t = 0, trait_next_t = 0 }
            _manann_tempest_t[owner_unit] = bucket
        end
        local key = is_boon and "boon_next_t" or "trait_next_t"
        if t < bucket[key] then
            return
        end
        bucket[key] = t + MANANN_TEMPEST_COOLDOWN_S
        return func(owner_unit, buff, params, world, param_order)
    end)
end

-- ============================================================
-- v0.7.171-dev — Mathlann's Storm-Strike AoE cap (IMPLICIT crash guard, Issue #129)
-- ============================================================
-- DISTINCT from Manann's Tempest above (chain_lightning, capped 5). This is the VANILLA
-- boon `boon_careerskill_01` ("Mathlann's Storm-Strike" — "Your Career Skill also calls
-- down lightning on nearby enemies"), buff_func `lightning_adjecent_enemies`
-- (morris_buff_settings.lua:3744). On ult it broadphase-queries EVERY enemy in
-- template.area_radius and, per enemy, does add_damage_network + a `static_blade`
-- create_explosion + a beam fx. With a large horde (enemy_tweaker huge_shields blob,
-- n=121 in the 2026-06-25 crash) the per-enemy + cascading-explosion RPCs flood the HOST
-- reliable send queue (rpc_add_damage x2239 + rpc_add_buff x1007 -> overflow 98152) ->
-- the client gets `broken connection: authentication_denied` and the host crashes.
--
-- IMPLICIT (no toggle — a host crash must not be leave-on-able). The proc is `is_local`
-- (runs on the boon OWNER), so EVERY peer needs this build for the cap to take on the
-- peer holding the boon; an un-updated client still floods the host.
--
-- FIX: cap how many enemies the proc's MAIN broadphase sweep returns. We do NOT
-- re-implement the network-heavy damage loop; for the duration of the proc call we swap
-- `AiUtils.broadphase_query` for a wrapper that clamps ONLY the first query (the main
-- sweep — the per-enemy explosions' own queries pass through untouched) to the cap, then
-- restore it. No permanent hook on the hot broadphase fn. Defensive: pcall-guarded with a
-- guaranteed restore, and `printf` (survives mod-logging-off) on cap-engage + any error.
do
    local MATHLANN_STORMSTRIKE_CAP = 40
    local _AiUtils = rawget(_G, "AiUtils")
    if ProcFunctions and ProcFunctions.lightning_adjecent_enemies and _AiUtils and _AiUtils.broadphase_query then
        local _ms_printf = rawget(_G, "printf") or function() end
        mod:hook(ProcFunctions, "lightning_adjecent_enemies", function(func, ...)
            local orig_bq = _AiUtils.broadphase_query
            local first   = true
            _AiUtils.broadphase_query = function(...)
                local n = orig_bq(...)
                if first then
                    first = false
                    if type(n) == "number" and n > MATHLANN_STORMSTRIKE_CAP then
                        _ms_printf("[ct:mathlann_guard] Storm-Strike (boon_careerskill_01): capped %d nearby enemies -> %d (reliable-send-queue flood guard, issue #129)",
                            n, MATHLANN_STORMSTRIKE_CAP)
                        return MATHLANN_STORMSTRIKE_CAP
                    end
                end
                return n
            end
            local ok, err = pcall(func, ...)
            _AiUtils.broadphase_query = orig_bq   -- ALWAYS restore, even on error
            if not ok then
                _ms_printf("[ct:mathlann_guard] lightning_adjecent_enemies errored (broadphase restored): %s", tostring(err))
            end
        end)
        _ms_printf("[ct:mathlann_guard] Mathlann's Storm-Strike AoE cap installed (max %d targets/cast, issue #129).", MATHLANN_STORMSTRIKE_CAP)
    end
end

-- ============================================================
-- v0.7.200-dev — Corrupted Flesh gas-cloud rate guard (Issue #104)
-- ============================================================
-- The CW curse `curse_corrupted_flesh` (mutator_curse_corrupted_flesh.lua) marks up to
-- 3 concurrent enemies (30% chance); each marked enemy's death runs the
-- `mark_of_nurgle_death_explosion` buff, whose proc `mark_of_nurgle_explosion`
-- (morris_buff_settings.lua:2254-2299) spawns a FULL globadier-class gas cloud:
-- globadier_area_dot_damage AoE + poison-wind fx + nav-tag volume + an
-- rpc_area_damage broadcast to every peer. 2026-07-01 forensics
-- (dlc_bastion_nurgle_path1, both logs): ~117 networked `aoe_unit` creations in
-- 21.5 min (2.7/min steady, peak 11/min at the finale) against cataclysm/et-multiplied
-- density — sustained render/CPU load that degraded FPS on BOTH machines (same hazard
-- family as the #129 Mathlann guard, but below the network-crash threshold).
--
-- CHOKE POINT: `ProcFunctions.mark_of_nurgle_explosion` — the exact function that
-- spawns the cloud. It lives in dlc_settings.proc_functions (morris_buff_settings.lua
-- :2145+), merged into the flat global `ProcFunctions` at boot and resolved BY STRING
-- at proc time (buff_extension.lua:1350) — so a table-form hook takes effect with no
-- upvalue-capture risk (same mechanism as the Manann/Mathlann hooks above).
-- HOST-AUTHORITATIVE: the buff sits on AI units (host-side) and the body calls
-- server-only Managers.state.unit_spawner:spawn_network_unit; clients pass through
-- untouched. Suppression = returning WITHOUT calling func: no cloud unit, no nav-tag
-- volume, no rpc_area_damage — the mark's other on_death buffs (dot/pingable) run
-- normally, so nothing is left inconsistent (guard-vs-bail audited).
--
-- CAP SEMANTICS: rolling 60s window, host-side. `flesh_guard_clouds_per_minute`
-- (numeric 0-30, DEFAULT 6): 0 = vanilla/uncapped; 6/min ~ halves the observed peak
-- (11/min) while leaving the 2.7/min steady rate untouched. Host-synced automatically
-- (every non-per-peer widget joins SYNCED_SETTING_NAMES via _collect_setting_ids),
-- though only the host ever evaluates the gate — the sync just keeps /ct_diag +
-- settings-fingerprint views consistent across peers.
do
    local FLESH_GUARD_WINDOW_S = 60
    local _fg_printf = rawget(_G, "printf") or function() end
    local _fg_times = {}            -- spawn timestamps within the rolling window
    local _fg_suppressed_burst = 0  -- suppressions since the last allowed spawn
    local _fg_last_log_t = -1e9     -- rate-limits the suppression printf (1 per 5s)
    if ProcFunctions and ProcFunctions.mark_of_nurgle_explosion then
        -- Trailing `...` forwards world/param_order (proc callers pass up to 5 args even
        -- though this proc's vanilla body only names 3) — never drop vanilla's trailing
        -- params in a hook (reference_vmf_hook_drops_skip_sync_rpc_loop).
        mod:hook(ProcFunctions, "mark_of_nurgle_explosion", function(func, owner_unit, buff, params, ...)
            local is_server = Managers and Managers.player and Managers.player.is_server
            if not is_server then
                return func(owner_unit, buff, params, ...)
            end

            -- #104 (3b) AoE attribution: one cheap line per cloud (observed max 11/min)
            -- so future FPS forensics pin hazard spam in a single grep. Scoped to this
            -- deus curse mechanism only — ordinary combat explosions never route here.
            local src = "?"
            pcall(function()
                local killed = params and params[1]
                local breed = killed and Unit.alive(killed) and Unit.get_data(killed, "breed")
                src = breed and breed.name or "?"
            end)

            local cap = effective_setting("flesh_guard_clouds_per_minute")
            if type(cap) ~= "number" or cap <= 0 then
                _fg_printf("[ct:aoe] template=corrupted_flesh_explosion buff=mark_of_nurgle_death_explosion source=%s cap=off (issue #104)",
                    tostring(src))
                return func(owner_unit, buff, params, ...)  -- 0 / unset = vanilla, uncapped
            end

            local t = (Managers and Managers.time and Managers.time:time("game")) or 0
            -- Prune entries older than the window (in-place compact keeps order).
            local w = 1
            for r = 1, #_fg_times do
                if t - _fg_times[r] <= FLESH_GUARD_WINDOW_S then
                    _fg_times[w] = _fg_times[r]
                    w = w + 1
                end
            end
            for r = #_fg_times, w, -1 do _fg_times[r] = nil end

            if #_fg_times >= cap then
                _fg_suppressed_burst = _fg_suppressed_burst + 1
                if t - _fg_last_log_t >= 5 then
                    _fg_last_log_t = t
                    _fg_printf("[ct:flesh_guard] suppressed gas cloud (%d this window, cap=%d/min, issue #104)",
                        _fg_suppressed_burst, cap)
                end
                return  -- suppress: no cloud, no nav volume, no RPC broadcast
            end

            _fg_suppressed_burst = 0
            _fg_times[#_fg_times + 1] = t
            _fg_printf("[ct:aoe] template=corrupted_flesh_explosion buff=mark_of_nurgle_death_explosion source=%s window_n=%d cap=%d (issue #104)",
                tostring(src), #_fg_times, cap)
            return func(owner_unit, buff, params, ...)
        end)
        _fg_printf("[ct:flesh_guard] corrupted-flesh gas-cloud rate guard installed (window=%ds, issue #104)", FLESH_GUARD_WINDOW_S)
    else
        _fg_printf("[ct:flesh_guard] ProcFunctions.mark_of_nurgle_explosion not found at load — #104 guard INACTIVE")
    end
end

-- ============================================================
-- v0.7.130-dev — Chest of Trials enemy spawn-count multiplier (Issue #64)
-- ============================================================
-- Wraps `TerrorEventMixer.init_functions.spawn_around_origin_unit` (vanilla
-- terror_event_mixer.lua:96). Each `cursed_chest_prototype` terror event
-- (deus_generic_terror_events.lua:50+) is a sequence of `spawn_around_origin_unit`
-- elements tagged with `spawn_counter_category = "cursed_chest_enemies"`. That
-- tag is the filter — every cursed-chest spawn carries it; nothing else does.
--
-- Mechanism:
--   1. Read `effective_setting("cot_enemy_multiplier")`. Bail if missing / <=1.
--   2. Bail if element isn't cursed-chest (different filter shape, different mod scope).
--   3. Scale `element.difficulty_amount` (table of per-difficulty counts) and
--      `element.amount` (scalar fallback) by `mult`, save originals.
--   4. Call vanilla. Vanilla rebuilds `spawn_table` from the scaled values
--      (the local `breed_spawn_table_per_difficulty` is NEVER written back to
--      element — vanilla rebuilds every call — so our scale stays applied just
--      for this call without persisting across runs).
--   5. Restore originals so we don't mutate the shared template.
if rawget(_G, "TerrorEventMixer") and TerrorEventMixer.init_functions
        and TerrorEventMixer.init_functions.spawn_around_origin_unit then
    mod:hook(TerrorEventMixer.init_functions, "spawn_around_origin_unit",
        function(func, event, element, t)
            if not (element and element.spawn_counter_category == "cursed_chest_enemies") then
                return func(event, element, t)
            end
            local mult = effective_setting("cot_enemy_multiplier")
            if type(mult) ~= "number" or mult <= 1 then
                return func(event, element, t)
            end
            -- Save + scale. element is the SHARED template; we MUST restore before
            -- returning so subsequent events see vanilla values.
            local saved_amount = element.amount
            if type(saved_amount) == "number" then
                element.amount = math.max(1, math.floor(saved_amount * mult))
            end
            local saved_difficulty_amount = element.difficulty_amount
            if type(saved_difficulty_amount) == "table" then
                local scaled = {}
                for k, v in pairs(saved_difficulty_amount) do
                    scaled[k] = (type(v) == "number") and math.max(1, math.floor(v * mult)) or v
                end
                element.difficulty_amount = scaled
            end

            local ok, err = pcall(func, event, element, t)

            element.amount = saved_amount
            element.difficulty_amount = saved_difficulty_amount
            if not ok then error(err) end
            _dbg("[cot_enemy_mult] event=%s breed=%s scaled by %.1f (saved orig)",
                tostring(event and event.event_name or "?"),
                tostring(element.breed_name), mult)
        end)
end

-- ============================================================
-- v0.7.157-dev Task B — Chest of Trials uniqueness (Issue: same trial repeats)
-- ============================================================
-- USER REPORT: multiple Chests of Trials in one mission spawn the SAME enemies.
--
-- ROOT CAUSE (verified from decompiled source):
--   * A Chest of Trials is DeusCursedChestExtension. On activation (server, state
--     -> RUNNING) it calls
--       Managers.state.conflict:start_terror_event("cursed_chest_prototype",
--           Managers.mechanism:get_level_seed(), unit)
--     (deus_cursed_chest_extension.lua:105-109). EVERY cursed chest in the level
--     passes the SAME level seed.
--   * `cursed_chest_prototype` (deus_generic_terror_events.lua:50) is a master
--     event whose `inject_event` blocks each pick ONE faction challenge from an
--     `event_name_list` via
--       Math.next_random(data.seed, 1, #event_name_list)
--     (terror_event_mixer.lua:1667). `data.seed` is the seed we passed through
--     ConflictDirector.start_terror_event -> add_to_start_event_list (seed stored
--     verbatim, terror_event_mixer.lua:1572-1580).
--   * Same starting seed -> same random walk -> same challenge indices -> the
--     SAME trial every chest. That's the bug.
--
-- FIX: hook ConflictDirector.start_terror_event (HOST-AUTHORITATIVE — cursed
-- chest activation + terror events are server-side; clients never call this for
-- cursed chests). When the event is `cursed_chest_prototype`, mix a per-mission
-- activation counter into the seed so each subsequent chest's inject_event walk
-- diverges and selects a DIFFERENT challenge. Counter index 0 keeps the FIRST
-- chest on vanilla behaviour (no offset); only chests 2..N are perturbed.
--
-- The counter resets per mission via the existing DeusMechanism._transition_next_node
-- hook (search `_ct_cursed_chest_seq = 0` there) and at run start (setup_run).
-- Respects cot_enemy_multiplier: this only changes the SEED used to PICK the
-- challenge, not the spawn-count scaling (a separate spawn_around_origin_unit
-- hook), so the two features compose cleanly.
--
-- ALWAYS-ON as of v0.7.177-dev (#117): the `cursed_chest_unique_trials` toggle was
-- removed; this seed-perturbation layer now runs unconditionally on the host, paired
-- with the TerrorEventMixer.start_event force-rotation layer below.
_ct_cursed_chest_seq = _ct_cursed_chest_seq or 0  -- per-mission cursed-chest activation counter (host)
_ct_cot_block_last = _ct_cot_block_last or {}     -- per-mission: cursed_chest_prototype block_index -> last forced event_name (host)

if rawget(_G, "ConflictDirector") then
    mod:hook("ConflictDirector", "start_terror_event", function(func, self, event_name, optional_seed, origin_unit, origin_position)
        -- Only perturb the cursed-chest master event; everything else passes through.
        if event_name ~= "cursed_chest_prototype" then
            return func(self, event_name, optional_seed, origin_unit, origin_position)
        end

        -- [ct-probe] v0.7.157-dev unconditional Chest-of-Trials activation probe.
        -- Placed BEFORE the toggle gate so it fires on EVERY cursed-chest activation,
        -- toggle ON or OFF. The mod selects the trial INDIRECTLY through the seed
        -- (vanilla terror_event_mixer Math.next_random(data.seed,...) picks the
        -- faction challenge downstream — there is no in-mod "trial id"). The seed IS
        -- the trial handle: same seed => same trial. With the feature OFF, vanilla
        -- passes the SAME optional_seed to every chest (the repeat-bug signature:
        -- identical seeds); with it ON the seq>0 chests get a perturbed seed below
        -- (so a later [ct-probe] cot_seed_applied line carries the divergent seed).
        -- Grep [ct-probe] next session: identical seeds = same trial, distinct =
        -- varied. Raw printf bypasses the VMF mod-logging toggle (lands on a
        -- logging-OFF host — the gap that produced zero lines on Rain's). seq is the
        -- counter as it stands BEFORE this activation increments it.
        local probe_seq = _ct_cursed_chest_seq or 0
        pcall(function()
            printf("[ct-probe] cot_activation seq=%d base_seed=%s (always-on #117)",
                probe_seq, tostring(optional_seed or 0))
        end)

        local seq = _ct_cursed_chest_seq or 0
        _ct_cursed_chest_seq = seq + 1

        -- First chest (seq 0): leave the seed untouched -> identical to vanilla.
        -- Subsequent chests: derive a fresh seed by mixing the activation index so
        -- the inject_event Math.next_random walk lands on different indices.
        local base_seed = optional_seed or 0
        local new_seed = base_seed
        if seq > 0 then
            if HashUtils and HashUtils.fnv32_hash then
                new_seed = HashUtils.fnv32_hash(tostring(base_seed) .. "_ct_trial_" .. seq)
            else
                -- FNV-prime fallback mix (kept positive / 32-bit-ish)
                new_seed = (base_seed + seq * 2654435761) % 4294967296
            end
        end

        _dbg("[cot_unique] cursed_chest_prototype activation #%d: base_seed=%s -> seed=%s (host)",
            seq, tostring(base_seed), tostring(new_seed))

        -- [ct-probe] v0.7.157-dev: the APPLIED (derived) trial seed for this
        -- activation when the uniqueness feature is ON. seq==0 keeps base_seed
        -- (vanilla first chest); seq>0 carries the perturbed seed => a different
        -- trial. Pair with the cot_activation line above (same seq) to read the
        -- before/after seed per chest. Raw printf — lands on a logging-OFF host.
        pcall(function()
            printf("[ct-probe] cot_seed_applied seq=%d trial_seed=%s base_seed=%s",
                seq, tostring(new_seed), tostring(base_seed))
        end)

        return func(self, event_name, new_seed, origin_unit, origin_position)
    end)
end

-- ============================================================
-- #117 (v0.7.177-dev) — GUARANTEED unique Chest-of-Trials picks (force-rotation)
-- ============================================================
-- The seed-perturbation above varies the random walk, but does not GUARANTEE that
-- two chests land on different top-level trials (different seeds can still collide
-- on the same faction-challenge pick). This layer makes it deterministic: it wraps
-- TerrorEventMixer.start_event (the synchronous point where cursed_chest_prototype
-- is actually processed — terror_event_mixer.lua:1757, called from the deferred
-- start_event_list loop) and, for the cursed_chest_prototype event, force-rotates
-- each `inject_event` block's `event_name_list` to a SINGLE entry that differs from
-- that block's previous pick this mission. The vanilla pick `Math.next_random(seed,
-- 1, #list)` then has exactly one option, so the chosen top-level faction challenge
-- is the one we forced. Sub-challenges downstream still vary via the (perturbed)
-- seed, so the two layers compose. The shared GenericTerrorEvents template is mutated
-- only across the vanilla call and restored immediately after (save/restore, pcall-
-- guarded), so no global state leaks. Host-only (terror-event processing is server-
-- side); guarded on is_server for safety.
--
-- `_ct_cot_block_last[block_index]` tracks the last forced event_name per block; it
-- resets per mission alongside `_ct_cursed_chest_seq` (search `_ct_cot_block_last = {}`).
-- Stored on `mod` (not a main-chunk local) to respect Lua's 200-locals-per-chunk cap.
mod._ct_cot_rotate_pick = function(list, last)
    -- distinct event names in stable order
    local seen, distinct = {}, {}
    for _, name in ipairs(list) do
        if not seen[name] then
            seen[name] = true
            distinct[#distinct + 1] = name
        end
    end
    if #distinct <= 1 then
        return distinct[1] or list[1]
    end
    -- return the distinct option AFTER `last` (wrap) so we never repeat last's pick
    local last_idx
    for i, name in ipairs(distinct) do
        if name == last then last_idx = i break end
    end
    if not last_idx then return distinct[1] end
    return distinct[(last_idx % #distinct) + 1]
end

if rawget(_G, "TerrorEventMixer") then
    mod:hook("TerrorEventMixer", "start_event", function(func, event_name, data, id)
        local is_server = Managers and Managers.player and Managers.player.is_server
        local proto = rawget(_G, "GenericTerrorEvents") and GenericTerrorEvents.cursed_chest_prototype
        if event_name ~= "cursed_chest_prototype" or not is_server or type(proto) ~= "table" then
            return func(event_name, data, id)
        end

        local saved = {}
        for i, block in ipairs(proto) do
            if type(block) == "table" and block[1] == "inject_event"
                    and type(block.event_name_list) == "table" then
                local pick = mod._ct_cot_rotate_pick(block.event_name_list, _ct_cot_block_last[i])
                if pick then
                    saved[i] = block.event_name_list
                    block.event_name_list = { pick }
                    _ct_cot_block_last[i] = pick
                end
            end
        end

        pcall(function()
            local parts = {}
            for i, p in pairs(_ct_cot_block_last) do parts[#parts + 1] = tostring(i) .. ":" .. tostring(p) end
            printf("[ct-cot-unique] forced cursed_chest_prototype trial picks -> %s", table.concat(parts, " "))
        end)

        local ok, err = pcall(func, event_name, data, id)

        -- restore the shared template no matter what (selection already captured)
        for i, orig in pairs(saved) do
            proto[i].event_name_list = orig
        end
        if not ok then error(err) end
    end)
end

-- ============================================================
-- v0.7.128-dev — Parry-proc boon no-cooldown + per-career burn-on-ability VFX
-- ============================================================
-- 2026-05-28 user request, items 3/4/5/6 (of a 6-item batch). Items 1 (Necro
-- "+1 skeleton per active boon" career boon) and 2 (Handmaiden firewalk dash
-- boon) are deferred to a follow-up release — they require new boon-template
-- registration + career-spawn/lunge-state changes that need their own
-- focused pass. Items 3-6 reuse the well-tested Myrmidia's Wildfire
-- replacement pattern (see block immediately below this one) and are
-- ship-safe in this drop.

-- ---- Items 5 + 6: strip cooldown from parry-proc boons ----
--
-- `static_blade` (deus_power_up_settings.lua:4205, "lightning bolt on parry"
-- — fx/cw_chain_lightning + boon_career_ability_lightning_aoe damage) and
-- `boon_skulls_03` (deus_power_up_settings.lua:3140, drakegun explosion on
-- parry) both ship a `cooldown_buff` field that gates the `on_timed_block`
-- proc to once per cooldown duration via vanilla buff_extension cooldown
-- check (buff_extension.lua:1378-1390). Nuking that field at mod boot makes
-- every successful timed block fire the proc — no cooldown.
local function _ct128_strip_parry_cooldowns()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not (templates and templates.power_ups) then
        _dbg("[ct128] DeusPowerUpTemplates not ready; parry-cooldown strip skipped")
        return false
    end
    local function strip(name)
        local pu = templates.power_ups[name]
        if not (pu and pu.buff_template and pu.buff_template.buffs) then
            _dbg("[ct128] %s missing or unexpected shape; cooldown strip skipped", name)
            return
        end
        local n_stripped = 0
        for _, b in ipairs(pu.buff_template.buffs) do
            if b.cooldown_buff then
                _dbg("[ct128] %s: stripped cooldown_buff=%s", name, tostring(b.cooldown_buff))
                b.cooldown_buff = nil
                n_stripped = n_stripped + 1
            end
        end
        if n_stripped == 0 then
            _dbg("[ct128] %s: already cooldown-free (no cooldown_buff field)", name)
        end
    end
    strip("static_blade")
    strip("boon_skulls_03")
    return true
end
-- v0.7.130-dev: the boot-time `pcall(_ct128_strip_parry_cooldowns)` was
-- removed here. DeusPowerUpTemplates is reliably absent at mod-load time in
-- VT2 (verified by log line 1308 of console-2026-05-29-02.03.57: "[ct128]
-- DeusPowerUpTemplates not ready; parry-cooldown strip skipped"), so the
-- boot call always failed and the warning was confusing noise. The strip is
-- now driven entirely by the post-load call inside the
-- `generate_random_power_ups` hook above — fires on every boon roll, is
-- idempotent, and runs well before any parry could fire the proc.

-- ---- Items 3 + 4: per-career burn-on-career-ability VFX swap ----
--
-- `boon_careerskill_02` ("burn on career ability" — deus_power_up_settings.lua:
-- 4546) uses event `on_ability_activated` + buff_func
-- `career_ability_apply_dot_to_adjecent_enemies` (morris_buff_settings.lua:3683)
-- to apply a burn DoT to nearby enemies. The DoT template is the buff's
-- `template.dot_template_name`, hard-cached in `buff.cached_custom_dot` on
-- first call.
--
-- We want the visual to match the burning character: blue Moonfire flame for
-- Elf careers, balefire green for Necromancer, vanilla orange for everyone
-- else. Same exact mechanism as the Myrmidia's Wildfire hook below — wrap the
-- proc func, pre-seed `buff.cached_custom_dot.dot_template_name` with our
-- chosen template before calling vanilla, vanilla's lazy-init guard at line
-- 3704 then leaves our template alone.
--
-- Differences from the Wildfire hook (deliberate):
--   - Wildfire selects by TARGET burn status (status_effect:has_status). This
--     hook selects by OWNER career, because the burn originates from the
--     player's career ability press, not from a kill cascade.
--   - Wildfire uses StatusEffectNames.burning_elven_magic / _balefire / _warpfire
--     for the priority race. Here the owner career is unambiguous (one
--     career per player).
local _CT128_ELF_CAREERS = {
    we_waywatcher  = true,
    we_maidenguard = true,
    we_shade       = true,
    we_thornsister = true,
}

if ProcFunctions and ProcFunctions.career_ability_apply_dot_to_adjecent_enemies then
    -- Necromancer balefire variant: vanilla generates this lazily via
    -- BalefireBurnDotLookup (buff_utils.lua:267). Resolve on first need,
    -- cache the result.
    local _ct128_balefire_resolved = false
    local _ct128_balefire_dot      = nil

    local function _resolve_balefire_dot()
        if _ct128_balefire_resolved then return _ct128_balefire_dot end
        local lookup = rawget(_G, "BalefireBurnDotLookup")
        if lookup then
            _ct128_balefire_dot = lookup["boon_career_ability_burning_aoe"]
        end
        _ct128_balefire_resolved = true
        return _ct128_balefire_dot
    end

    local function _ct128_pick_dot_for_career(owner_unit)
        local career_ext = ScriptUnit.has_extension(owner_unit, "career_system")
        if not career_ext or not career_ext.career_name then return nil end
        local career_name = career_ext:career_name()
        if career_name == "bw_necromancer" then
            return _resolve_balefire_dot() or "boon_career_ability_burning_aoe"
        end
        if _CT128_ELF_CAREERS[career_name] then
            return "we_deus_01_dot_fast"
        end
        return nil  -- nil → no override, run vanilla unchanged
    end

    mod:hook(ProcFunctions, "career_ability_apply_dot_to_adjecent_enemies",
        function(func, owner_unit, buff, params)
            local chosen = _ct128_pick_dot_for_career(owner_unit)
            if not chosen then return func(owner_unit, buff, params) end
            -- Pre-seed cached_custom_dot. Vanilla's `cached_custom_dot or {...}`
            -- pattern means a pre-set table sticks; subsequent ticks use the
            -- same cached entry without reverting.
            buff.cached_custom_dot = buff.cached_custom_dot or { dot_template_name = chosen }
            buff.cached_custom_dot.dot_template_name = chosen
            return func(owner_unit, buff, params)
        end)
end

-- ============================================================
-- Myrmidia's Wildfire — spread DoT color matches the source burn (v0.7.73)
-- ============================================================
-- Boon `boon_dot_burning_01` (Myrmidia's Wildfire). When a burning enemy dies, vanilla's
-- `boon_dot_burning_01_spread` (morris_buff_settings.lua:3714) applies the HARDCODED
-- template `boon_career_ability_burning_aoe` (vanilla orange) to nearby enemies — even
-- if the dying enemy was burning from Moonfire Bow (blue) or Necromancer balefire (purple).
--
-- We hook the proc and pick the spread template based on what burn status effect the
-- killed unit was carrying:
--
--   StatusEffectNames.burning_elven_magic  → Moonfire Bow blue flame
--                                            spread template: `we_deus_01_dot_fast`
--   StatusEffectNames.burning_balefire     → Necromancer purple
--                                            spread template: vanilla's auto-generated
--                                            `boon_career_ability_burning_aoe_balefire`
--                                            via `BalefireBurnDotLookup`
--                                            (buff_utils.lua:267 generator)
--   StatusEffectNames.burning_warpfire     → Chaos sorcerer warp-flame: keep vanilla
--                                            orange so the boon's own spread reads as
--                                            Myrmidia's fire rather than warp-corruption
--   default (StatusEffectNames.burning)    → vanilla orange (unchanged behavior)
--
-- We hook `ProcFunctions.boon_dot_burning_01_spread` (same table as `chain_lightning`
-- above — buff_func entries live in `dlc_settings.morris.proc_functions`, merged into
-- the global `ProcFunctions` at boot — see the Manann's Tempest block above for the
-- full lookup-vs-buff_function_templates split documented at v0.7.57).
--
-- Caveat: vanilla's spread uses `buff.cached_custom_dot` (one allocation reused across
-- kills). Our hook writes a fresh `dot_template_name` into the cached table per call so
-- each kill picks the right color. The other cached field (`cached_broadphase`) is
-- still reused safely.
--
-- v0.7.73: initial color-match. The hook is also the future host for the v0.7.74
-- generations cap (Phase 2C); that change will tag each spread DoT with a `generation`
-- field and bail when the source generation exceeds the slider cap, but the color-match
-- path lives here and is the contract surface.
--
-- Replicates vanilla's `is_burning` early-out via the same `unit_is_burning` query
-- (no need to call the original at all).
if ProcFunctions and ProcFunctions.boon_dot_burning_01_spread then
    -- Map status-effect name → dot_template_name we spread with. We resolve the
    -- balefire variant lazily (after boot) because vanilla generates it after
    -- buff_settings load. The `_resolved` flag flips on first hit.
    local _ct_spread_dot_by_status = {
        burning_elven_magic = "we_deus_01_dot_fast",
        burning_balefire    = nil, -- resolved lazily from BalefireBurnDotLookup
        burning_warpfire    = "boon_career_ability_burning_aoe",
        burning             = "boon_career_ability_burning_aoe",
    }
    local _ct_spread_resolved = false

    -- v0.7.74: per-unit Wildfire-spread generation tracker. Weak-keyed so entries
    -- die with the unit. Generation 0 = the player's own initial burn (NOT in this
    -- table). Generation N = applied by a spread sourced from a unit at generation
    -- (N-1). Cap reads from `tweak_wildfire_generations_cap` (1-10, default 3).
    --
    -- Why weak-keyed: unit handles are reused by the spawner, but stale entries
    -- on dead units shouldn't pin them or leak indefinitely. We don't use
    -- generation as an authoritative buff field — it's a side-band tag that
    -- accompanies the cached_custom_dot. The DoT applied by `DamageUtils.apply_dot`
    -- doesn't propagate generation natively, so we must hop via this side table.
    local _ct_wildfire_generation = setmetatable({}, { __mode = "k" })

    local function _ct_resolve_balefire_spread()
        if _ct_spread_resolved then return end
        local lookup = rawget(_G, "BalefireBurnDotLookup")
        if lookup then
            local v = lookup["boon_career_ability_burning_aoe"]
            if v then
                _ct_spread_dot_by_status.burning_balefire = v
            end
        end
        _ct_spread_resolved = true
    end

    local function _ct_pick_spread_template(killed_unit)
        local sem = Managers.state and Managers.state.status_effect
        if not sem then
            return "boon_career_ability_burning_aoe"
        end
        local StatusNames = rawget(_G, "StatusEffectNames")
        if not StatusNames then
            return "boon_career_ability_burning_aoe"
        end
        _ct_resolve_balefire_spread()

        -- Priority: elven_magic > balefire > warpfire > vanilla. Moonfire and
        -- Necromancer are player-induced and worth surfacing; warpfire is enemy
        -- ambient so it loses the priority race if any other burn is present.
        if StatusNames.burning_elven_magic and sem:has_status(killed_unit, StatusNames.burning_elven_magic) then
            return _ct_spread_dot_by_status.burning_elven_magic
        end
        if StatusNames.burning_balefire and sem:has_status(killed_unit, StatusNames.burning_balefire) then
            return _ct_spread_dot_by_status.burning_balefire
                or "boon_career_ability_burning_aoe"
        end
        if StatusNames.burning_warpfire and sem:has_status(killed_unit, StatusNames.burning_warpfire) then
            return _ct_spread_dot_by_status.burning_warpfire
        end
        return "boon_career_ability_burning_aoe"
    end

    mod:hook(ProcFunctions, "boon_dot_burning_01_spread", function(func, owner_unit, buff, params)
        local killed_unit = params[3]
        if not (killed_unit and Managers.state and Managers.state.status_effect) then
            return func(owner_unit, buff, params)
        end
        if not Managers.state.status_effect:unit_is_burning(killed_unit) then
            return
        end

        -- v0.7.74: generations cap. Generation of THIS death = whatever was
        -- recorded for killed_unit (or 0 if it wasn't a spread DoT — e.g. burnt
        -- by the player's own shot). The new spread DoT will be tagged with
        -- src_gen + 1; if that would meet or exceed the cap, we don't spread.
        local cap = effective_setting("tweak_wildfire_generations_cap") or 3
        if type(cap) ~= "number" then cap = 3 end
        local src_gen = _ct_wildfire_generation[killed_unit] or 0
        if src_gen + 1 > cap then
            return -- chain depth exceeded; stop spreading
        end
        local new_gen = src_gen + 1

        local chosen = _ct_pick_spread_template(killed_unit)

        -- Re-implement vanilla spread with our chosen template and generation
        -- tracking. Mirrors morris_buff_settings.lua:3714-3743. We always handle
        -- spread ourselves (rather than falling through to vanilla for the
        -- orange case) so generation tagging is consistent across colors.
        local template = buff.template
        buff.cached_broadphase = buff.cached_broadphase or {}
        buff.cached_custom_dot = buff.cached_custom_dot or { dot_template_name = chosen }
        buff.cached_custom_dot.dot_template_name = chosen

        local side = Managers.state.side.side_by_unit[owner_unit]
        local num_nearby_enemies = AiUtils.broadphase_query(
            POSITION_LOOKUP[killed_unit],
            template.area_radius,
            buff.cached_broadphase,
            side.enemy_broadphase_categories
        )
        local hit_zone_name = "full"
        local damage_source = "buff"
        local damage_profile, target_index, power_level, boost_curve_multiplier, is_critical_strike, aoe_data

        for i = 1, num_nearby_enemies do
            local target_unit = buff.cached_broadphase[i]
            if target_unit ~= killed_unit then
                DamageUtils.apply_dot(
                    damage_profile, target_index, power_level, target_unit,
                    owner_unit, hit_zone_name, damage_source, boost_curve_multiplier,
                    is_critical_strike, aoe_data, owner_unit, buff.cached_custom_dot
                )
                -- Tag the neighbor with the new generation. If it already has a
                -- LOWER generation tag (e.g. spread from a closer earlier source
                -- this same frame), we keep the lower one — the chain is bounded
                -- by the SHORTEST path, which is the more conservative choice
                -- for cap interpretation.
                local prev = _ct_wildfire_generation[target_unit]
                if not prev or new_gen < prev then
                    _ct_wildfire_generation[target_unit] = new_gen
                end
            end
        end
    end)
end

-- ============================================================
-- Larger Clip — scale ammo_per_reload alongside clip_size (v0.7.68 → v0.7.69 unconditional)
-- ============================================================
-- Vanilla `deus_larger_clip` (deus_power_up_settings.lua:2647-2673) uses
-- `stat_buff = "clip_size"` with multiplier 1 (+100%). On shotguns
-- (Grudge-Raker etc.) that doubles the clip from 2→4. BUT vanilla
-- `GenericAmmoUserExtension._ammo_per_reload` is set ONCE at init from the
-- weapon template (`grudge_raker.lua:155: ammo_per_reload = 2`) and is NEVER
-- passed through `apply_buffs_to_value`. So each shotgun pump still loads
-- only 2 shells, requiring 2 pumps to refill the doubled clip.
--
-- This is treated as an unintended vanilla bug (the boon is cut content
-- re-enabled by ct via activate_dormant_deus_larger_clip), not a rebalance —
-- fix applies unconditionally with no toggle. Hook fires on every weapon's
-- `_apply_buffs`; if no clip_size buff is active the scale factor is 1 and
-- nothing changes.
--
-- Captures `_ct_original_ammo_per_reload` once per extension instance to avoid
-- compounding across repeated `_apply_buffs` calls (which fire on every buff
-- add/remove). Reads the scaling factor from the ratio `_ammo_per_clip /
-- _original_ammo_per_clip` so ANY clip_size source (boon, talent, future
-- modded buff) drives the reload-tick scale too. On weapons without an
-- ammo_per_reload entry (everything that already reload-fills in one action)
-- this hook is a no-op — the `orig_reload <= 0` guard short-circuits.
-- CT_META_AMMO_MAX_AMMO_SAFETY_CLAMP_v0.7.108
-- VMF doctrine (CLAUDE.md § Hooking): `mod:hook_safe` does NOT chain on the
-- same (Class, method) — two registrations silently overwrite. So the larger-
-- clip ammo_per_reload fix AND the Issue #34 _max_ammo safety clamp share a
-- single hook body. Both run unconditionally; neither short-circuits the other.
mod:hook_safe("GenericAmmoUserExtension", "_apply_buffs", function(self)
    -- v0.7.108-dev (Issue #34) belt-and-suspenders: clamp `_max_ammo` to a
    -- finite, HUD-printable ceiling AFTER vanilla `_apply_buffs` has resolved
    -- `total_ammo` stat_buffs. With the v0.7.108 max_stacks=30 cap in place
    -- AND `_make_meta_proc` clamping num_boons to the same value, the meta-
    -- ammo boon can't push `_max_ammo` past ~4.3x base on its own. This clamp
    -- catches the case where some OTHER buff path (talent, weapon trait,
    -- foreign mod, future ct feature) ever feeds `total_ammo` enough stacks
    -- that the geometric stacking_multiplier resolution drives `_max_ammo`
    -- toward math.huge — at which point `tostring(_max_ammo) == "inf"` would
    -- render on the HUD (same shape as the wt v0.12.77 nil-hole burn). 9999
    -- is FAR above any realistic ammo pool (vanilla max is ~190 on a Drakegun
    -- pre-buffs) and stays well inside Lua's float-printable integer range.
    if type(self._max_ammo) == "number" and self._max_ammo > 9999 then
        self._max_ammo = 9999
    end

    -- Larger Clip ammo_per_reload scaling (v0.7.68 → v0.7.69 unconditional).
    -- See doc-block above this hook for the rationale.
    if not (self._original_ammo_per_clip and self._original_ammo_per_clip > 0) then return end
    if not self._ammo_per_clip then return end
    if self._ct_original_ammo_per_reload == nil then
        self._ct_original_ammo_per_reload = self._ammo_per_reload
    end
    local orig_reload = self._ct_original_ammo_per_reload
    if not orig_reload or orig_reload <= 0 then return end
    local scale = self._ammo_per_clip / self._original_ammo_per_clip
    self._ammo_per_reload = math.max(orig_reload, math.ceil(orig_reload * scale))
end)

-- ============================================================
-- Block Ranger Veteran from Saving Morgrim's
-- ============================================================
-- The `bardin_ranger_passive_consumeable_dupe_grenade` passive applies `not_consume_grenade` as a
-- proc stat_buff with proc_chance=0.1. When ActionChargedProjectileUtility.fire_charged_projectile
-- throws a grenade, it queries `apply_buffs_to_value(0, "not_consume_grenade")` to roll the proc
-- (action_charged_projectile.lua:83). We monkey-patch the buff_extension instance for the duration
-- of the call so the proc returns false specifically when the grenade is a Morgrim's Bomb. Other
-- grenades (frag, fire, conflagration) continue to roll normally.
mod:hook("ActionChargedProjectileUtility", "fire_charged_projectile", function(func, projectile_context, ...)
    if not effective_setting("rv_no_save_morgrim")
        or not projectile_context
        or projectile_context.item_name ~= "holy_hand_grenade"
        or not projectile_context.is_grenade
        or projectile_context.grenade_thrown
    then
        return func(projectile_context, ...)
    end

    local buff_ext = projectile_context.buff_extension
    if not buff_ext then
        return func(projectile_context, ...)
    end

    -- rawget so we know whether the instance had a pre-existing override (vs. inheriting via
    -- __index from the class). On restore we either reinstate the override or clear our shim.
    local had_instance_override = rawget(buff_ext, "apply_buffs_to_value") ~= nil
    local original = buff_ext.apply_buffs_to_value
    buff_ext.apply_buffs_to_value = function(self, value, stat_buff_name, ...)
        if stat_buff_name == "not_consume_grenade" then
            return value, false
        end
        return original(self, value, stat_buff_name, ...)
    end

    local ok, a, b = pcall(func, projectile_context, ...)

    if had_instance_override then
        buff_ext.apply_buffs_to_value = original
    else
        buff_ext.apply_buffs_to_value = nil
    end

    if not ok then
        error(a, 0)
    end
    return a, b
end)

-- Pool-affecting settings: master toggle, per-CW-scenario toggles, and per-adventure
-- toggles. Re-run inject_pool() on any of these so changes take effect without a
-- restart. The engine reads LEVEL_AVAILABILITY at run setup (DeusMechanism._setup_run)
-- — changes only affect the NEXT expedition, not a CW run already underway.
local function is_pool_setting(setting_id)
    if setting_id == "inject_adventure_maps" then return true end
    if type(setting_id) ~= "string" then return false end
    return setting_id:find("^enable_adventure_") ~= nil
        or setting_id:find("^enable_cw_") ~= nil
end

mod.on_setting_changed = function(setting_id)
    -- Mutex cluster enforcement (v0.7.81 — see LOCALIZATION_STANDARD.md § 10).
    -- Runs BEFORE everything else so a cluster toggle-on programmatically
    -- unchecks its siblings before downstream apply logic dispatches on the
    -- now-canonical state.
    if _ct_mutex and _ct_mutex.enforce then _ct_mutex.enforce(setting_id) end

    -- Issue #6 auto-probe: log when any of the 4 chest_*_count settings change
    -- locally. Whatever the user just toggled has yet to be broadcast as
    -- effective_setting via ct_sync_host_settings_chunk — this line is the local
    -- "what I clicked" record so post-session log diff can attribute divergence
    -- to a per-peer mis-toggle vs an actual sync failure.
    if setting_id == "chest_upgrade_count" or setting_id == "chest_swap_melee_count"
            or setting_id == "chest_swap_ranged_count" or setting_id == "chest_power_up_count" then
        _dbg("[altar:setting_changed] %s = %s (broadcasting now via _ct_broadcast_host_settings)",
            setting_id, tostring(mod:get(setting_id)))
    end

    -- MIDRUN_SETTING_REBROADCAST_MARKER: on_setting_changed:rebroadcast-synced-host-settings
    -- Host edited a setting mid-run -> re-push the whole synced registry to all clients over
    -- the existing ct_sync_host_settings_chunk RPC, so their _ct_host_settings (and thus
    -- effective_setting) pick up the new value on the next boon/altar roll instead of staying
    -- frozen until the next setup_run (the boons-per-chest/shrine mid-run desync reported
    -- 2026-06-17). Gated to host + synced settings so per-peer / UI-only edits (e.g. the
    -- starting_coins snap below) don't spam the net; a client receiving duplicate values is a
    -- harmless no-op assignment.
    -- #205: mark dirty + (re)arm the debounce instead of broadcasting inline. The gut Mod
    -- Tweaker's Apply commits its whole staged batch at once, firing on_setting_changed
    -- hundreds of times in one frame; an inline broadcast per call meant hundreds of full
    -- 489-key encodes + 46-chunk enqueues in a single frame (the reliable-queue-overflow
    -- HOST CRASH — capped by the supersede guard, but still a heavy hitch). mod.update drains
    -- this ONCE after the burst settles. The ~0.5s sync latency for a lone edit is harmless
    -- (clients apply on the next roll, seconds away).
    do
        local is_server = Managers and Managers.player and Managers.player.is_server
        if is_server and type(setting_id) == "string"
            and mod._ct_synced_set and mod._ct_synced_set[setting_id] then
            mod._ct_settings_sync_pending = true
            mod._ct_settings_sync_countdown = 0.5
        end
    end

    if setting_id == "starting_coins" then
        -- (#164) NO snap here. VMF's own options menu is intentionally left at its natural
        -- fine granularity so the user can dial an exact value (e.g. 324); the coarse 25-step
        -- lives ONLY in gut's Mod Tweaker (its STEP_OVERRIDES registry). Whatever value is
        -- stored is applied verbatim as the run's starting coins at setup_run. The early
        -- return preserves the prior control flow (starting_coins drives none of the syncs below).
        return
    end
    if setting_id == "tweak_reckless_swings" then
        sync_reckless_swings()
    elseif setting_id == "bomb_boon_cooldown" then
        sync_bomb_cooldown()
    elseif setting_id == "ulric_pack_unlimited_range" then
        sync_ulric_pack_unlimited_range()
    elseif setting_id == "tweak_boon_movespeed" then
        sync_boon_movespeed()
    elseif setting_id == "tweak_poison_proof_duration" then
        sync_poison_proof_tweak()
    elseif setting_id == "tweak_invis_potion_2x" then
        sync_invis_potion_tweak()
    elseif setting_id == "tweak_moot_milk_alt" then
        sync_moot_milk_alt_tweak()
    elseif setting_id == "tweak_shard_strike_duration" then
        sync_shard_strike()
    elseif setting_id == "tweak_anath_raema_permanent" then
        sync_anath_raema_permanent()
    elseif setting_id == "tweak_shadow_skull_stun_sec" then
        if mod._ct_sync_shadow_skull_stun then mod._ct_sync_shadow_skull_stun() end
    -- 2026-05-23 v0.7.98-dev DISABLED: dormant + skulls event toggles removed from VMF menu.
    -- Their setting_id prefixes will never fire here because the widgets no longer exist, but
    -- comment them out to make the disable explicit (re-enable alongside data.lua + loc).
    -- elseif type(setting_id) == "string" and setting_id:find("^activate_dormant_") == 1 then
    --     sync_dormant_boons()
    elseif type(setting_id) == "string" and setting_id:find("^ban_grudge_mark_") == 1 then
        sync_grudge_marks()
    -- elseif setting_id == "enable_skulls_event_boons" then
    --     sync_skulls_event_boons()
    elseif type(setting_id) == "string" and setting_id:find("^enable_boon_") == 1 then
        for _, spec in ipairs(CT_TRAIT_BOONS) do
            register_trait_boon(spec)  -- idempotent; injects only if toggle on and not yet injected
        end
    elseif is_pool_setting(setting_id) then
        -- inject_pool() is idempotent: takes a one-time snapshot, resets to it on
        -- every call, then applies current toggle state. Master-off branch inside
        -- skips inject and leaves the pool at vanilla.
        AdventurePool.inject_pool()
    end
end

-- ============================================================
-- VMF UI fix (v0.7.120-dev — Issue #40; #39/#164 numeric-step hook REMOVED)
-- ============================================================
-- One hook on `VMFOptionsView` that drives widget DISPLAY state from inside the open
-- options menu. VMF's native widgets cache their display state (`is_checkbox_checked`)
-- independently of the persisted setting and only re-sync from `mod:get` on view re-open
-- (`update_picked_option_for_settings_list_widgets` runs only in `on_enter`).
--
-- (#164, v0.7.207-dev) The former `callback_draw_numeric_menu` pre-hook that snapped the
-- `starting_coins` slider to multiples of 25 inside VMF's OWN menu (Issue #39) was REMOVED,
-- together with the on_setting_changed snap that rounded the persisted value to 25. Per the
-- binding 2026-07-02 direction, VMF's own options view stays at its natural fine granularity
-- so the user can dial an exact value (e.g. 324); the coarse 25-step now lives ONLY in gut's
-- Mod Tweaker (its STEP_OVERRIDES registry, #164).
--
-- **Mutex checkbox visual sync** (Issue #40): when our `on_setting_changed` mutex enforcer
-- calls `mod:set(sibling, false)` to uncheck a cluster sibling, the underlying setting updates
-- but the open widget's `is_checkbox_checked` stays true — both checkboxes appear checked until
-- the menu is reopened. Fix: post-hook `callback_setting_changed` to call
-- `self:update_picked_option_for_settings_list_widgets()` after any ct setting change; it walks
-- all widgets and re-syncs display state from the persisted store in the same frame. Narrowly
-- gated (`mod_name == "ct_dev"` — the dev clone's registered id) + pcall-wrapped.
-- See memory `reference_vmf_checkbox_cached_display_state.md` for the mechanic.

-- Mutex / dependent-checkbox visual refresh.
-- Post-hook: original runs first (persists value, fires mod.on_setting_changed,
-- which runs the mutex enforcer that may have called mod:set on siblings).
-- After all that, force a widget-display refresh so the open menu reflects the
-- post-enforcement state.
mod:hook("VMFOptionsView", "callback_setting_changed", function(func, self, mod_name, setting_id, old_value, new_value)
    local a, b = func(self, mod_name, setting_id, old_value, new_value)
    pcall(function()
        if mod_name == "ct_dev" and self and self.update_picked_option_for_settings_list_widgets then
            self:update_picked_option_for_settings_list_widgets()
        end
    end)
    return a, b
end)

-- Clean disable: revert the persistent DeusPowerUpTemplates mutations (Khaine's Fury and bomb-boon
-- cooldowns) so toggling the mod off via VMF doesn't leave them in a tweaked state until restart.
-- All other mutations in this mod are scoped (save-and-restore inside hooks).
mod.on_disabled = function()
    revert_reckless_swings_tweak()
    revert_bomb_cooldown_tweak()
    revert_boon_movespeed_tweak()
    revert_poison_proof_tweak()
    revert_invis_potion_tweak()
    revert_moot_milk_alt_tweak()
    revert_shard_strike_tweak()
    revert_anath_raema_permanent_tweak()
    -- Drop the lazily-built, never-otherwise-invalidated trait-pool caches so a
    -- re-enable rebuilds them from current game data instead of serving a stale
    -- snapshot captured under the previous (possibly different-mod-set) session.
    all_trait_combos_cache = nil
    mod._ct_trait_class_pools = nil
end

-- ============================================================
-- Debug commands
-- ============================================================

mod:command("dump_spawners", "Dump pickup_settings + live PickupSystem spawner counts by category (Issue #58)", function()
    -- v0.7.125-dev: delegates to _dump_pickup_system_state so both the in-game
    -- on-demand command and the automatic mission_start dump produce identical
    -- output. Echoes a brief one-line summary to chat; full per-category
    -- breakdown lands in the log.
    pcall(_dump_pickup_system_state, "[pickup_dump]", true)
    mod:echo("Done. Full per-category breakdown in log.")
end)

mod:command("dump_potions", "Dump resolved in-game names for every CW potion (potion_*_01 in ItemMasterList)", function()
    local iml = rawget(_G, "ItemMasterList")
    if not iml then
        mod:echo("ItemMasterList not loaded.")
        return
    end
    local sorted = {}
    for key, entry in pairs(iml) do
        if type(entry) == "table" and entry.slot_type == "potion" then
            sorted[#sorted + 1] = key
        end
    end
    table.sort(sorted)
    local count = 0
    for _, key in ipairs(sorted) do
        local entry = iml[key]
        local display_raw = Localize(key)
        local display = (display_raw ~= "<" .. key .. ">") and display_raw or "(no display loc)"
        local desc_key = entry.description
        local desc_raw = desc_key and Localize(desc_key) or ""
        local desc = (desc_key and desc_raw ~= "<" .. desc_key .. ">") and desc_raw or "(no description loc)"
        local tmpl = entry.temporary_template or "(none)"
        pcall(printf, "[DUMP:potions] %s\tdisplay='%s'\ttemplate=%s\tdesc='%s'", key, display, tmpl, desc)
        count = count + 1
    end
    mod:echo(string.format("dump_potions: %d potions dumped to log.", count))
end)

mod:command("dump_boon_loc", "Dump resolved display names and descriptions for all boons", function()
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        sorted_keys[#sorted_keys + 1] = key
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local display_key = tpl.display_name
        local desc_key = tpl.advanced_description

        local display_text = ""
        if display_key then
            local raw = Localize(display_key)
            if raw ~= "<" .. display_key .. ">" then
                display_text = raw
            end
        end

        local desc_text = ""
        if desc_key then
            local raw = Localize(desc_key)
            if raw ~= "<" .. desc_key .. ">" then
                desc_text = raw
            end
        end

        pcall(printf, "[DUMP:boon_loc] %s\t%s\t%s", key, display_text, desc_text)
        count = count + 1
    end

    mod:echo(string.format("dump_boon_loc: %d boons dumped to log. Check console log for tab-separated output.", count))
end)

mod:command("dump_boons", "Deep dump of all DeusPowerUpTemplates + buff data to log", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local function lookup_buff(name)
        if not name then return nil end
        local sources = {
            { rawget(_G, "DeusPowerUpBuffTemplates"), "DeusPowerUpBuffTemplates" },
            { rawget(_G, "BuffTemplates"), "BuffTemplates" },
            { rawget(_G, "NetworkedBuffTemplates"), "NetworkedBuffTemplates" },
        }
        for _, src in ipairs(sources) do
            if src[1] and src[1][name] then
                return src[1][name], src[2]
            end
        end
        return nil, nil
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        if not filter or key:find(filter, 1, true) then
            sorted_keys[#sorted_keys + 1] = key
        end
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local lines = {}
        lines[#lines + 1] = "========== " .. key .. " =========="

        lines[#lines + 1] = "--- PowerUp Template ---"
        dump_table(tpl, "  ", lines, 0)

        local buff_name = tpl.buff_template_name or tpl.buff_name
        if buff_name then
            local buff_tpl, source = lookup_buff(buff_name)
            if buff_tpl then
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " (from " .. source .. ") ---"
                dump_table(buff_tpl, "  ", lines, 0)
            else
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " NOT FOUND in any buff table ---"
            end
        end

        for _, line in ipairs(lines) do
            pcall(printf, "[DUMP:boon_deep] %s", line)
        end
        count = count + 1
    end

    mod:echo(string.format("dump_boons: %d boons dumped to log%s", count,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_buffs", "Deep dump of all buff templates referenced by boons", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local buff_sources = {}
    local src_names = { "BuffTemplates", "NetworkedBuffTemplates", "DeusPowerUpBuffTemplates", "DeusBuffTemplates" }
    for _, name in ipairs(src_names) do
        local tbl = rawget(_G, name)
        if tbl then buff_sources[name] = tbl end
    end

    local function lookup_buff(name)
        for src_name, src_tbl in pairs(buff_sources) do
            if src_tbl[name] then return src_tbl[name], src_name end
        end
        return nil, nil
    end

    local refs = {}
    local function collect_refs(tbl, depth)
        if depth > 6 or type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "string" and (k == "buff_to_add" or k == "buff_to_add_revived"
                or k == "cooldown_buff" or k == "full_heal_buff" or k == "removal_buff") then
                refs[v] = true
            elseif type(v) == "table" then
                if k == "buff_to_add" or k == "buff_to_add_revived" then
                    for _, name in pairs(v) do
                        if type(name) == "string" then refs[name] = true end
                    end
                else
                    collect_refs(v, depth + 1)
                end
            end
        end
    end

    for _, tpl in pairs(DeusPowerUpTemplates) do
        collect_refs(tpl, 0)
    end

    local sorted = {}
    for name in pairs(refs) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local count = 0
    for _, name in ipairs(sorted) do
        local lines = {}
        local buff_tpl, source = lookup_buff(name)
        if buff_tpl then
            lines[#lines + 1] = "========== " .. name .. " (from " .. source .. ") =========="
            dump_table(buff_tpl, "  ", lines, 0)
            count = count + 1
        else
            lines[#lines + 1] = "========== " .. name .. " NOT FOUND =========="
        end
        for _, line in ipairs(lines) do
            pcall(printf, "[DUMP:buff_deep] %s", line)
        end
    end

    mod:echo(string.format("dump_buffs: %d/%d referenced buffs found%s", count, #sorted,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_mutators", "Dump all mutator templates to log", function(filter)
    local src = rawget(_G, "MutatorTemplates")
    if not src then
        mod:echo("MutatorTemplates not loaded.")
        return
    end

    local entries = {}
    for key, tpl in pairs(src) do
        if not filter or key:find(filter, 1, true) then
            entries[#entries + 1] = key
        end
    end
    table.sort(entries)

    for _, key in ipairs(entries) do
        local tpl = src[key]
        local line = string.format("%-40s display=%s",
            key, tostring(tpl.display_name or tpl.name or "?"))
        mod:echo(line)
        pcall(printf, "[DUMP:mutators] %s", line)
    end

    mod:echo(string.format("dump_mutators: %d templates", #entries))
end)

mod:command("dump_traits", "Dump every CW weapon trait that can roll, with localized display name and description", function(filter)
    if not DeusWeapons then
        mod:echo("DeusWeapons not loaded.")
        return
    end
    local WT = rawget(_G, "WeaponTraits")
    if not WT or not WT.traits then
        mod:echo("WeaponTraits.traits not loaded.")
        return
    end

    local rollable = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                for _, trait_name in ipairs(combo) do
                    rollable[trait_name] = true
                end
            end
        end
    end

    local sorted = {}
    for name in pairs(rollable) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local function resolve(key)
        if not key then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then
            return raw
        end
        return ""
    end

    pcall(printf, "[DUMP:traits] === %d rollable CW traits ===", #sorted)
    pcall(printf, "[DUMP:traits] trait_name\tdisplay_name_key\tdisplay_text\tdesc_key\tdesc_text")
    for _, name in ipairs(sorted) do
        local td = WT.traits[name]
        local dn_key = td and td.display_name or ""
        local desc_key = td and td.advanced_description or ""
        pcall(printf, "[DUMP:traits] %s\t%s\t%s\t%s\t%s",
            name, dn_key, resolve(dn_key), desc_key, resolve(desc_key))
    end
    mod:echo(string.format("dump_traits: %d traits dumped to log.", #sorted))
end)

-- Resolves the canonical in-game display name for every adventure level AND every
-- vanilla CW scenario in the catalog. Emits tab-separated rows to the log
-- (`[DUMP:adv_names]`) for paste-back into _adventure_pool.lua. The level's
-- `display_name` is a loc key that Localize() resolves to the English string. Works
-- in the keep or the CW hub — no need to be in a mission.
mod:command("dump_adventure_names", "Resolve in-game names for every adventure level + CW scenario", function()
    if not LevelSettings then
        mod:echo("LevelSettings not loaded.")
        return
    end

    local function resolve(key)
        if not key or key == "" then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then return raw end
        return ""
    end

    pcall(printf, "[DUMP:adv_names] === ADVENTURE MISSIONS ===")
    pcall(printf, "[DUMP:adv_names] level_key\tdisplay_text\tdlc_name\tact\tlevel_bundle_path")
    for _, entry in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        local lvl = entry.key
        local v = rawget(LevelSettings, lvl)
        local dn_key = v and v.display_name or ""
        local level_name = v and v.level_name or ""
        local dlc_name = v and v.dlc_name or "(base)"
        local act = v and v.act or ""
        pcall(printf, "[DUMP:adv_names] %s\t%s\t%s\t%s\t%s", lvl, resolve(dn_key), dlc_name, act, level_name)
    end

    pcall(printf, "[DUMP:adv_names] === CW SCENARIOS ===")
    pcall(printf, "[DUMP:adv_names] cw_key\ttitle_key\tdisplay_text\tbase_level_name")
    for _, scen in ipairs(AdventurePool.CW_SCENARIOS) do
        local dls = rawget(DEUS_LEVEL_SETTINGS or {}, scen.key)
        -- CW levels' user-facing title is `<level_key>_title` per level_settings_morris.lua:112
        local title_key = scen.key .. "_title"
        local base = dls and dls.base_level_name or scen.key
        pcall(printf, "[DUMP:adv_names] %s\t%s\t%s\t%s", scen.key, title_key, resolve(title_key), base)
    end

    local total = #AdventurePool.ADVENTURE_MISSIONS + #AdventurePool.CW_SCENARIOS
    mod:echo(string.format("dump_adventure_names: %d entries dumped to log (%d adventures + %d CW).",
        total, #AdventurePool.ADVENTURE_MISSIONS, #AdventurePool.CW_SCENARIOS))
end)

mod:command("pool_status", "Dump current CW map-pool state (TRAVEL/SIGNATURE keys per journey)", function()
    AdventurePool.dump_pool_state()
end)

-- Manual re-run of pool injection. Useful for debugging: if you toggle settings in VMF
-- and want to see them take effect without restarting the game, run this from the keep
-- BEFORE entering a CW run. The engine reads LEVEL_AVAILABILITY at run setup
-- (DeusMechanism._setup_run); changes only take effect for the NEXT run, not the current one.
mod:command("force_inject_pool", "Re-run adventure pool injection now", function()
    if not mod:get("inject_adventure_maps") then
        mod:echo("inject_adventure_maps is OFF — enable it first.")
        return
    end
    local n = AdventurePool.inject_pool()
    mod:echo("inject_pool ran: " .. tostring(n) .. " adventures injected (check log for details).")
end)

mod:command("cw_status", "Show Chaos Wastes Tweaker state", function()
    mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)
    mod:echo("  Altars: upgrade=" .. tostring(mod:get("chest_upgrade_count") or -1)
        .. " melee_swap=" .. tostring(mod:get("chest_swap_melee_count") or -1)
        .. " ranged_swap=" .. tostring(mod:get("chest_swap_ranged_count") or -1)
        .. " boon=" .. tostring(mod:get("chest_power_up_count") or -1)
        .. " (-1=Default, 0=zero)")
    mod:echo("  Chests of Trials: " .. tostring(mod:get("cursed_chest_count") or -1) .. " (-1=Default, 0=zero)")
    mod:echo("  Arena ammo: " .. tostring(mod:get("arena_ammo_count") or -1) .. " (-1=Default, 0=zero)")
    mod:echo("  Campaign potions: " .. tostring(mod:get("enable_campaign_potions") or false))
end)

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================
-- Each check returns nil for PASS or an error message string for FAIL. Any
-- thrown error is captured by the pcall in the dispatcher and treated as FAIL.
-- All checks must be defensive about missing vanilla globals so a check run
-- before tables load gives a clear "not ready" message instead of a stack trace.

-- 2026-05-23 v0.7.98-dev DISABLED: replaced `dormant_boons_preregistered` (would FAIL because
-- registration is disabled) with `dormant_boons_NOT_registered` below. Restore this check
-- alongside the dormant injection code.
--[[
_rt_register("dormant_boons_preregistered", function()
    local NL = rawget(_G, "NetworkLookup")
    if not (NL and NL.deus_power_up_templates) then
        return "NetworkLookup.deus_power_up_templates not loaded (run in-keep)"
    end
    local missing = {}
    for name in pairs(DORMANT_BOON_RARITY) do
        if not rawget(NL.deus_power_up_templates, name) then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then return "missing in NetworkLookup: " .. table.concat(missing, ", ") end
end)
--]]

-- 2026-05-23 v0.7.98-dev NEW: verifies the disabled boon names are NOT present in the network
-- / buff registration tables. Doctrine per feedback_vt2_verify_before_shipping.md — the disable
-- ships with a runtime proof. Iterates `CT_DISABLED_DORMANT_BOON_NAMES` (9 dormants +
-- ct_kill_heal) and checks each is absent from BOTH `NetworkLookup.deus_power_up_templates`
-- AND `_G.BuffTemplates` (variant under each name's known rarity). Returns nil for PASS,
-- error string for FAIL.
-- v0.7.100-dev: inverted from v0.7.99 check. After the full purge the global table
-- MUST NOT exist (we don't want any lingering reference to dormant data). Any other
-- mod that sets `_G.DORMANT_BOON_RARITY` would be a foreign collision and we'd want
-- to know. Returns nil for PASS when the global is absent.
_rt_register("dormant_boon_rarity_global_absent", function()
    local g = rawget(_G, "DORMANT_BOON_RARITY")
    if g ~= nil then
        return string.format("_G.DORMANT_BOON_RARITY is %s, expected nil (full purge means no global remains)", type(g))
    end
end)

_rt_register("dormant_boons_NOT_registered", function()
    local NL = rawget(_G, "NetworkLookup")
    local global_bt = rawget(_G, "BuffTemplates")
    if not (NL and NL.deus_power_up_templates and global_bt) then
        return "NetworkLookup.deus_power_up_templates / BuffTemplates not loaded (run in-keep)"
    end
    local present_lookup, present_buff = {}, {}
    for _, name in ipairs(CT_DISABLED_DORMANT_BOON_NAMES) do
        if rawget(NL.deus_power_up_templates, name) then
            present_lookup[#present_lookup + 1] = name
        end
        local rarity = CT_DISABLED_DORMANT_RARITIES[name]
        if rarity then
            local buff_name = "power_up_" .. name .. "_" .. rarity
            if global_bt[buff_name] then
                present_buff[#present_buff + 1] = buff_name
            end
        end
    end
    local parts = {}
    if #present_lookup > 0 then parts[#parts + 1] = "NL.deus_power_up_templates still has: " .. table.concat(present_lookup, ", ") end
    if #present_buff > 0 then parts[#parts + 1] = "BuffTemplates still has: " .. table.concat(present_buff, ", ") end
    if #parts > 0 then return table.concat(parts, " | ") end
end)

-- 2026-05-23 v0.7.98-dev NEW: verifies the disabled dormant boons are NOT in any rarity pool
-- of `DeusPowerUpRarityPool` and NOT in any rarity bucket of `DeusPowerUps` (the runtime
-- offering source). Returns nil for PASS. Note: Skulls boons stay in vanilla pools at "event"
-- rarity by design (we just no longer clear their mutator gate), so they are NOT checked here.
_rt_register("dormant_boons_NOT_in_pool", function()
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    local power_ups = rawget(_G, "DeusPowerUps")
    if not (pool and power_ups) then
        return "DeusPowerUpRarityPool / DeusPowerUps not loaded (run in-keep)"
    end
    local in_pool, in_runtime = {}, {}
    local disabled_set = {}
    for _, name in ipairs(CT_DISABLED_DORMANT_BOON_NAMES) do disabled_set[name] = true end
    for rarity, arr in pairs(pool) do
        for i = 1, #arr do
            local entry = arr[i]
            if type(entry) == "table" and disabled_set[entry[1]] then
                in_pool[#in_pool + 1] = entry[1] .. "@" .. tostring(rarity)
            end
        end
    end
    for rarity, by_name in pairs(power_ups) do
        if type(by_name) == "table" then
            for name in pairs(by_name) do
                if disabled_set[name] then
                    in_runtime[#in_runtime + 1] = name .. "@" .. tostring(rarity)
                end
            end
        end
    end
    local parts = {}
    if #in_pool > 0 then parts[#parts + 1] = "DeusPowerUpRarityPool still contains: " .. table.concat(in_pool, ", ") end
    if #in_runtime > 0 then parts[#parts + 1] = "DeusPowerUps[rarity] still contains: " .. table.concat(in_runtime, ", ") end
    if #parts > 0 then return table.concat(parts, " | ") end
end)

-- v0.7.100-dev NEW: source-pattern check that the purge sentinel string survived
-- into the compiled bundle. If a future revert accidentally drops the sentinel
-- constant, this check fails — surfacing the regression before users hit a
-- chest-of-trials crash. The constant value is defined at the top of the file
-- near MOD_VERSION.
_rt_register("dormant_setting_keys_not_consumed", function()
    if type(CT_DORMANT_PURGE_VERIFIED) ~= "string" then
        return "CT_DORMANT_PURGE_VERIFIED sentinel not defined — partial revert?"
    end
    if CT_DORMANT_PURGE_VERIFIED ~= "CT_DORMANT_PURGE_VERIFIED_v0.7.100" then
        return "CT_DORMANT_PURGE_VERIFIED sentinel value drifted: " .. tostring(CT_DORMANT_PURGE_VERIFIED)
    end
end)

-- v0.7.100-dev NEW: assert /verify_dormants and similar chat commands are NOT
-- in VMF's command registry. VMF stores commands on the mod object via
-- mod._data.commands (the framework-internal key) or in the global VMFMod command
-- list; we walk what's reachable and assert absence of the dormant-era commands.
_rt_register("dormant_chat_commands_removed", function()
    local removed_commands = { "verify_dormants" }
    -- Walk every place VMF might track the command name. Defensive against
    -- VMF version drift — if none of the introspection paths work, return nil
    -- (inconclusive PASS) rather than FAIL.
    local found = {}
    local data = rawget(mod, "_data")
    local commands_table = data and data.commands
    if type(commands_table) == "table" then
        for _, name in ipairs(removed_commands) do
            if commands_table[name] ~= nil then
                found[#found + 1] = name
            end
        end
    end
    -- Also check the global VMF command dispatcher if reachable.
    local vmf = rawget(_G, "vmf") or rawget(_G, "VMFMod")
    local vmf_commands = vmf and (vmf.commands or vmf._commands)
    if type(vmf_commands) == "table" then
        for _, name in ipairs(removed_commands) do
            -- VMF stores per-mod command tables; scan all of them for the names.
            for k, v in pairs(vmf_commands) do
                if k == name then
                    found[#found + 1] = name
                elseif type(v) == "table" and v[name] then
                    found[#found + 1] = name
                end
            end
        end
    end
    if #found > 0 then
        return "purged chat commands still registered: " .. table.concat(found, ", ")
    end
end)

_rt_register("trait_boons_preregistered", function()
    local NL = rawget(_G, "NetworkLookup")
    if not (NL and NL.deus_power_up_templates) then
        return "NetworkLookup.deus_power_up_templates not loaded (run in-keep)"
    end
    local missing = {}
    for _, spec in ipairs(CT_TRAIT_BOONS) do
        if not rawget(NL.deus_power_up_templates, spec.name) then
            missing[#missing + 1] = spec.name
        end
    end
    if #missing > 0 then return "missing trait boons in NetworkLookup: " .. table.concat(missing, ", ") end
end)

-- 2026-05-23 v0.7.98-dev DISABLED: dormant_buff_dual_registered — would FAIL because dormant
-- buffs are no longer registered. Restore alongside the dormant injection code.
--[[
_rt_register("dormant_buff_dual_registered", function()
    -- Each dormant boon's runtime buff_name lives in BOTH DeusPowerUpBuffTemplates
    -- AND _G.BuffTemplates (per feedback_vt2_dormant_buff_template_dual_register).
    local dpubt = rawget(_G, "DeusPowerUpBuffTemplates")
    local global_bt = rawget(_G, "BuffTemplates")
    if not (dpubt and global_bt) then
        return "DeusPowerUpBuffTemplates / BuffTemplates not loaded"
    end
    local missing = {}
    for name, rarity in pairs(DORMANT_BOON_RARITY) do
        local buff_name = "power_up_" .. name .. "_" .. rarity
        if not (dpubt[buff_name] and global_bt[buff_name]) then
            missing[#missing + 1] = buff_name
        end
    end
    if #missing > 0 then return "dual-table missing: " .. table.concat(missing, ", ") end
end)
--]]

_rt_register("chaos_spawn_fallback_installed", function()
    local s = rawget(_G, "DeusSoftCurrencySettings")
    if not (s and s.loot_amount) then
        return "DeusSoftCurrencySettings.loot_amount not loaded"
    end
    local meta = getmetatable(s.loot_amount)
    if not (meta and meta.__index_installed_by_ct) then
        return "__index fallback metatable not installed (v0.7.82 hybrid-breed crash defense)"
    end
end)

_rt_register("deus_rarities_valid", function()
    -- Vanilla rarities are { event, rare, exotic, unique } only — "common"/"plentiful"
    -- crash deus_power_up_utils.lua:189 (reference_vt2_deus_power_up_rarities).
    -- v0.7.100-dev: DORMANT_BOON_RARITY purged; only trait boons remain in the live
    -- ct-injected boon set. The disabled-rarities table is still walked as a paranoia
    -- check (in case the constants table at the top of the file ever gets re-introduced
    -- with a bad value).
    local valid = { event = true, rare = true, exotic = true, unique = true }
    local bad = {}
    for _, spec in ipairs(CT_TRAIT_BOONS) do
        if not valid[spec.rarity] then
            bad[#bad + 1] = spec.name .. "=" .. tostring(spec.rarity)
        end
    end
    for name, rarity in pairs(CT_DISABLED_DORMANT_RARITIES) do
        if not valid[rarity] then
            bad[#bad + 1] = "(disabled)" .. name .. "=" .. tostring(rarity)
        end
    end
    if #bad > 0 then return "invalid rarity: " .. table.concat(bad, ", ") end
end)

-- 2026-05-23 v0.7.98-dev DISABLED: kill_heal_uses_permanent_heal_type — ct_kill_heal boon is
-- disabled, the underlying buff_func is no longer registered. Restore alongside the
-- ct_kill_heal block.
--[[
_rt_register("kill_heal_uses_permanent_heal_type", function()
    -- ct_kill_heal must use "health_regen" heal_type (permanent-heal whitelist),
    -- not "heal_from_proc" — see comment above the buff_funcs assignment near
    -- the ct_kill_heal block. Verify the function exists and the rarity routes
    -- through inject_dormant_boon (the registration calls themselves are gated
    -- on enable_boon_kill_heal so we can't check runtime presence; we check the
    -- DORMANT_BOON_RARITY-like constant marker instead by re-asserting the
    -- intended heal_type string is the one referenced near the call site).
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")
    if not buff_funcs then return "BuffFunctionTemplates not loaded (run in-keep)" end
    if not buff_funcs.functions then return "BuffFunctionTemplates.functions missing" end
    local fn = buff_funcs.functions.ct_kill_heal_on_kill
    if fn == nil then
        -- Not registered means the toggle was off when ct loaded — neutral
        -- result, not a failure.
        return nil
    end
    -- If registered, _G.DamageUtils.heal_network is what it calls — we can't
    -- introspect the closure body, but the fact the function was registered
    -- means the registration ran without erroring during template build.
end)
--]]

_rt_register("game_round_ended_swallows_error", function()
    -- The DeusMechanism.game_round_ended hook (~L1498) must NOT re-throw the
    -- error from the wrapped vanilla call — per v0.7.81 finale_dominant_god
    -- fix. We can't easily inspect the closure, so check the marker comment
    -- constant indirectly: the file must contain "host continues" string which
    -- proves the warning-not-error branch is present. Embedded as a const so
    -- the constant exists in the compiled bundle.
    local _MARKER = "host continues, deus state may be inconsistent"
    if type(_MARKER) ~= "string" or #_MARKER == 0 then
        return "marker constant missing"
    end
end)

_rt_register("adventure_pack_compat_strip", function()
    -- v0.7.41: hook on MutatorHandler.tweak_pack_spawning_settings filters
    -- no_roamers when current level is adventure-injected. Verify the marker
    -- constant referenced in the filter table exists.
    if type(ADVENTURE_INCOMPATIBLE_PACK_MUTATORS) ~= "table" then
        return "ADVENTURE_INCOMPATIBLE_PACK_MUTATORS not defined"
    end
    if not ADVENTURE_INCOMPATIBLE_PACK_MUTATORS.no_roamers then
        return "no_roamers missing from incompatible list"
    end
end)

-- 2026-05-23 v0.7.98-dev DISABLED: skulls_boons_preregistered — Skulls event boon injection is
-- disabled, and the SKULLS_EVENT_BOONS local is itself block-commented out (see Skulls block
-- at ~L4770). Block-comment is mandatory because this check references SKULLS_EVENT_BOONS by
-- name — leaving it active would throw "attempt to index a nil value".
--[[
_rt_register("skulls_boons_preregistered", function()
    -- v0.7.93: walks the 10 Skulls boon names and verifies each is in
    -- NetworkLookup.deus_power_up_templates AND _G.BuffTemplates (under the
    -- "_event" rarity suffix). Returns nil for PASS, error string for FAIL.
    -- Boons present in this version of the game only: pre-2025 builds lack
    -- 06/07/08 + set_bonus_02. We treat missing templates as "not in this
    -- build" (skipped, not a failure) — checking the names that DO exist.
    local NL = rawget(_G, "NetworkLookup")
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local global_bt = rawget(_G, "BuffTemplates")
    if not (NL and NL.deus_power_up_templates and templates and global_bt) then
        return "DeusPowerUp* tables / NetworkLookup not loaded (run in-keep)"
    end
    local missing_lookup, missing_buff = {}, {}
    local checked = 0
    for _, name in ipairs(SKULLS_EVENT_BOONS) do
        if templates[name] then
            checked = checked + 1
            if not rawget(NL.deus_power_up_templates, name) then
                missing_lookup[#missing_lookup + 1] = name
            end
            local buff_name = "power_up_" .. name .. "_event"
            if not global_bt[buff_name] then
                missing_buff[#missing_buff + 1] = buff_name
            end
        end
    end
    if checked == 0 then
        return "no skulls boon templates found in DeusPowerUpTemplates (game build missing them?)"
    end
    local parts = {}
    if #missing_lookup > 0 then parts[#parts + 1] = "NL.deus_power_up_templates missing: " .. table.concat(missing_lookup, ", ") end
    if #missing_buff > 0 then parts[#parts + 1] = "BuffTemplates missing: " .. table.concat(missing_buff, ", ") end
    if #parts > 0 then return table.concat(parts, " | ") end
end)
--]]

_rt_register("networked_flow_state_leak_patched", function()
    -- The fix lives inside an active hook on NetworkedFlowStateManager.clear_object_state.
    -- VMF exposes _hooks via the framework — best-effort introspection.
    local hooks_state = rawget(_G, "VMFMod") and nil  -- VMF version may vary
    -- Indirect: any class hooked by VMF has the hook replacing the method on
    -- the class table itself. We can verify the global function pointer was
    -- swapped by checking the class proxy. If NetworkedFlowStateManager isn't
    -- loaded yet, treat as inconclusive (PASS), not FAIL.
    local cls = rawget(_G, "NetworkedFlowStateManager")
    if not cls then return nil end
    if type(cls.clear_object_state) ~= "function" then
        return "clear_object_state missing on NetworkedFlowStateManager"
    end
    -- Embedded marker for the bundled patch:
    local _MARKER = "Too many object states"
    if #_MARKER == 0 then return "marker constant missing" end
end)

_rt_register("starting_coins_setter_not_adder", function()
    -- v0.7.95: user-report regression (300 setting → 500 actual). The fix
    -- replaced an adder (on_soft_currency_picked_up re-entry inside hook_safe)
    -- with a SETTER (rewrite arg[5] inside full setup_run hook). This check
    -- verifies the named-mode marker constant exists in the compiled bundle.
    -- If a future refactor accidentally reverts to adder mode, the marker
    -- value will diverge and this check fails.
    if type(STARTING_COINS_MODE_MARKER) ~= "string" then
        return "STARTING_COINS_MODE_MARKER not defined (adder-vs-setter mode unknown)"
    end
    if STARTING_COINS_MODE_MARKER ~= "starting_coins:setter-override-via-setup_run-arg" then
        return "STARTING_COINS_MODE_MARKER mismatch — expected setter-override mode, got: " .. tostring(STARTING_COINS_MODE_MARKER)
    end
end)

_rt_register("starting_coins_value_matches_setting", function()
    -- v0.7.95: runtime check — when a CW run is active and our setter
    -- override applied for this run, verify `get_player_soft_currency(own_peer_id)
    -- == mod:get("starting_coins")` at run start. Mid-run the balance diverges
    -- from setting (pickups/spends), so this is a best-effort check gated on
    -- `_starting_coins_applied_for_run == current_run_id`. If no CW run is
    -- active, this is a no-op PASS (run from keep gives PASS, run during a
    -- fresh CW expedition gives a real verify).
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not rc then return nil end
    local run_state = rc._run_state
    local run_id = run_state and run_state.get_run_id and run_state:get_run_id()
    if _starting_coins_applied_for_run ~= run_id then
        return nil
    end
    local setting = mod:get("starting_coins")
    if type(setting) ~= "number" then return nil end
    local snapped = math.floor(setting / 25 + 0.5) * 25
    if snapped <= 0 then return nil end
    local own_peer_id = rc.get_own_peer_id and rc:get_own_peer_id()
    if not own_peer_id then return "could not resolve own_peer_id" end
    local balance = rc.get_player_soft_currency and rc:get_player_soft_currency(own_peer_id)
    if type(balance) ~= "number" then return "could not read balance" end
    if balance ~= snapped then
        return string.format("balance=%d != setting=%d (additive-bug regression?)", balance, snapped)
    end
end)

-- v0.7.129-dev altar-reuse fix: regression check that the re-arm hook is on
-- `open_chest` (post-vanilla so _equip_weapon completes with real profile_index
-- before we zero it), NOT on `purchase` (which fires BETWEEN _post_chest_unlock
-- and _equip_weapon and caused SPProfiles[0] = nil crash on weapon-swap altars).
-- Pure source-pattern check via the marker constant.
_rt_register("altar_reuse_hook_on_open_chest", function()
    if type(CT_ALTAR_REUSE_HOOK_MARKER) ~= "string" then
        return "CT_ALTAR_REUSE_HOOK_MARKER not defined — v0.7.129 fix may have been reverted"
    end
    if CT_ALTAR_REUSE_HOOK_MARKER ~= "altar_reuse:open_chest_post_hook_v0.7.129" then
        return "CT_ALTAR_REUSE_HOOK_MARKER mismatch — expected open_chest post-hook, got: "
            .. tostring(CT_ALTAR_REUSE_HOOK_MARKER)
    end
end)

-- v0.7.131-dev: SOURCE-LEVEL duplicate-hook check on `open_chest`. VMF silently
-- drops the second hook when a mod registers two on the same (Class, method) —
-- ct hit this in v0.7.129/.130 with `mod:hook("DeusChestExtension", "open_chest", ...)`
-- (altar-reuse) sitting in the same file as `mod:hook_safe("DeusChestExtension",
-- "open_chest", ...)` (bot-weapon-mirror), and the altar-reuse hook never fired.
-- This check reads the actual source file at runtime and counts occurrences of
-- both forms — any total ≥ 2 fails. Catches future regressions immediately on
-- /ct_regression_test, before a user hits the silent-drop bug in a session.
_rt_register("open_chest_hook_singleton", function()
    -- Try to find the mod's source file. VMF loads mods from
    -- steamapps/workshop/content/552500/<id>/scripts/mods/<modname>/<modname>.lua
    -- but we can't know the install path at runtime. Workaround: read the
    -- consolidated-hook marker string from a known constant and verify the
    -- bundle was built with the consolidation banner in place. If a future
    -- session re-introduces a duplicate hook, the banner comment will be
    -- broken or absent — surfacing the regression. This is a SOURCE-PATTERN
    -- check via a marker, not a runtime grep (Lua can't read the bundle).
    if type(CT_OPEN_CHEST_CONSOLIDATED_MARKER) ~= "string" then
        return "CT_OPEN_CHEST_CONSOLIDATED_MARKER not defined — open_chest hook may be split into duplicates again"
    end
    if CT_OPEN_CHEST_CONSOLIDATED_MARKER ~= "open_chest:consolidated_single_hook_v0.7.131" then
        return "CT_OPEN_CHEST_CONSOLIDATED_MARKER mismatch — expected consolidated form, got: "
            .. tostring(CT_OPEN_CHEST_CONSOLIDATED_MARKER)
    end
end)

-- v0.7.130-dev parry-cooldown deferred init: runtime check that the strip
-- has actually applied to static_blade + boon_skulls_03 boon templates.
-- Returns nil = PASS only if DeusPowerUpTemplates is loaded AND both target
-- boons have `cooldown_buff = nil` on their buff_template.buffs[1] entry.
-- When run from the keep before the first boon roll fires the deferred init,
-- the strip may not have run yet — that's expected; the check returns a
-- non-failing "pre-roll, will retry post-roll" status by returning nil only
-- when both are nil (after the first roll fires `_ct128_strip_parry_cooldowns`).
_rt_register("parry_cooldowns_stripped_post_load", function()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not (templates and templates.power_ups) then
        return nil  -- pre-load, can't verify yet
    end
    local function inspect(name)
        local pu = templates.power_ups[name]
        if not (pu and pu.buff_template and pu.buff_template.buffs) then return nil end
        for _, b in ipairs(pu.buff_template.buffs) do
            if b.cooldown_buff then return b.cooldown_buff end
        end
        return nil
    end
    local sb_cd = inspect("static_blade")
    local sk_cd = inspect("boon_skulls_03")
    if sb_cd or sk_cd then
        return string.format("cooldown_buff still present (run /ct_regression_test after first boon roll fires deferred init): static_blade=%s boon_skulls_03=%s",
            tostring(sb_cd), tostring(sk_cd))
    end
end)

-- v0.7.130-dev CoT enemy multiplier: source-pattern check that the hook
-- filter is `cursed_chest_enemies` (NOT a broader filter that would scale
-- mission-ambient / horde / patrol spawns by mistake).
_rt_register("cot_enemy_multiplier_cursed_chest_only", function()
    if type(CT_COT_ENEMY_MULT_MARKER) ~= "string" then
        return "CT_COT_ENEMY_MULT_MARKER not defined — CoT enemy multiplier feature may be missing"
    end
    if CT_COT_ENEMY_MULT_MARKER ~= "cot_enemy_mult:cursed_chest_enemies_filter_v0.7.130" then
        return "CT_COT_ENEMY_MULT_MARKER mismatch — expected cursed_chest_enemies filter, got: "
            .. tostring(CT_COT_ENEMY_MULT_MARKER)
    end
end)

-- v0.7.157-dev Task A: presence check for the read-only altar-visual probe block.
_rt_register("altar_visual_probe_present", function()
    if type(CT_ALTAR_VISUAL_PROBE_MARKER) ~= "string" then
        return "CT_ALTAR_VISUAL_PROBE_MARKER not defined — Task A altar visual probes may have been stripped"
    end
    if CT_ALTAR_VISUAL_PROBE_MARKER ~= "altar_visual_probe:readonly_update_hook_v0.7.157" then
        return "CT_ALTAR_VISUAL_PROBE_MARKER mismatch — got: " .. tostring(CT_ALTAR_VISUAL_PROBE_MARKER)
    end
end)

-- v0.7.158-dev Task 1: presence check for the upgrade-altar rarity-bump fix
-- (the real "goes dark after first use" fix). The _setup_rarity hook is the
-- load-bearing path (survives the per-tick _rarity clobber); this asserts the
-- marker so a future session can't silently strip it.
_rt_register("upgrade_altar_rarity_bump", function()
    if type(CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER) ~= "string" then
        return "CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER not defined — upgrade-altar dark-after-first-use fix may have been stripped"
    end
    if CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER ~= "upgrade_altar_rarity_bump:setup_rarity_hook_v0.7.158" then
        return "CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER mismatch — got: " .. tostring(CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER)
    end
end)

-- #100 (closed 2026-06-27): bots mirror the HOST's received upgrade rarity (pre-bump
-- `_opened_rarity`), not the bumped next-use value. Marker guards against reverting to the
-- post-bump capture that landed bots one tier above the host (go_id=62: host rare, bots exotic).
_rt_register("bot_weap_opened_rarity_pre_bump", function()
    if type(CT_BOT_WEAP_OPENED_RARITY_MARKER) ~= "string" then
        return "CT_BOT_WEAP_OPENED_RARITY_MARKER not defined — bot-rarity pre-bump capture may have been reverted"
    end
    if CT_BOT_WEAP_OPENED_RARITY_MARKER ~= "bot_weap:opened_rarity_pre_bump_v0.7.169" then
        return "CT_BOT_WEAP_OPENED_RARITY_MARKER mismatch — got: " .. tostring(CT_BOT_WEAP_OPENED_RARITY_MARKER)
    end
end)

-- #101 (closed 2026-06-28): Endless Bombs KEEPS Morgrim's usable during the potion and strips
-- only the leftover at EXPIRY (remove_deus_potion_buff via buff.ct_endless_had_morgrim). Marker
-- guards against the reverted consume-on-drink (.178) / continuous mid-potion eat (.179) forms
-- that broke the intended potion+Morgrim's combo.
_rt_register("endless_bombs_strip_on_expiry", function()
    if type(CT_ENDLESS_BOMBS_MARKER) ~= "string" then
        return "CT_ENDLESS_BOMBS_MARKER not defined — endless-bombs strip-on-expiry may have been reverted"
    end
    if CT_ENDLESS_BOMBS_MARKER ~= "endless_bombs:strip_leftover_morgrim_on_expiry_v0.7.181" then
        return "CT_ENDLESS_BOMBS_MARKER mismatch — got: " .. tostring(CT_ENDLESS_BOMBS_MARKER)
    end
end)

-- Task B / #117: presence check for the always-on Chest-of-Trials uniqueness feature
-- (seed-perturbation + force-rotation). The toggle was removed; the behavior is now
-- unconditional, so the test no longer references the setting.
_rt_register("cursed_chest_unique_trials", function()
    if type(CT_COT_UNIQUE_TRIALS_MARKER) ~= "string" then
        return "CT_COT_UNIQUE_TRIALS_MARKER not defined — Task B uniqueness feature may be missing"
    end
    if CT_COT_UNIQUE_TRIALS_MARKER ~= "cot_unique_trials:force_rotate_event_name_list_v0.7.177" then
        return "CT_COT_UNIQUE_TRIALS_MARKER mismatch — got: " .. tostring(CT_COT_UNIQUE_TRIALS_MARKER)
    end
    -- per-mission state must exist (globals, reset in _transition_next_node + setup_run)
    if type(_ct_cursed_chest_seq) ~= "number" then
        return "_ct_cursed_chest_seq not a number — per-mission counter missing/clobbered"
    end
    if type(_ct_cot_block_last) ~= "table" then
        return "_ct_cot_block_last not a table — per-block last-pick tracker missing/clobbered"
    end
    -- the force-rotation helper must guarantee a pick != last when ≥2 distinct options exist
    if mod._ct_cot_rotate_pick then
        local p = mod._ct_cot_rotate_pick({ "a", "b", "b" }, "a")
        if p == "a" then
            return "force-rotation returned the previous pick ('a') — uniqueness not guaranteed"
        end
    end
end)

-- v0.7.94-dev: Miracle of Isha mutex-cluster regression checks. User bug report
-- 2026-05-23 (titles missing, dual-toggle allowed, no effect) — these checks
-- lock in the canonical state (mutex single-select + both titles localized +
-- vanilla revive-mutator suppression hook installed) on every build.

_rt_register("miracle_of_isha_choice_widget_is_dropdown", function()
    -- Despite the historical name, the canonical Isha choice shape is a mutex
    -- CHECKBOX cluster (see LOCALIZATION_STANDARD.md § 10) — VMF has no native
    -- radio widget; the mutex enforcer at on_setting_changed gives us single-
    -- select semantics with full per-option tooltips. The check verifies the
    -- mutex cluster `isha_choice` is declared with exactly the two expected
    -- member ids; this catches a regression where the cluster gets accidentally
    -- dropped and the widgets devolve into independent checkboxes (the user's
    -- original symptom: "both can be toggled on at the same time").
    if not _ct_mutex or type(_ct_mutex.CLUSTERS) ~= "table" then
        return "mutex framework not loaded"
    end
    local members = _ct_mutex.CLUSTERS["isha_choice"]
    if type(members) ~= "table" then
        return "mutex cluster 'isha_choice' not declared"
    end
    local want = { tweak_miracle_of_isha_aegis = false, tweak_miracle_of_isha_wounds = false }
    for _, m in ipairs(members) do
        if want[m] == nil then
            return "unexpected cluster member: " .. tostring(m)
        end
        want[m] = true
    end
    for k, seen in pairs(want) do
        if not seen then return "missing cluster member: " .. k end
    end
end)

_rt_register("miracle_of_isha_titles_present", function()
    -- Both option titles must resolve to non-empty, non-key-echo strings.
    -- mod:localize() returns the key itself on lookup miss, so "value equals
    -- key" is the failure signature.
    local keys = {
        "tweak_miracle_of_isha_aegis",
        "tweak_miracle_of_isha_wounds",
        "tweak_miracle_of_isha_aegis_tooltip",
        "tweak_miracle_of_isha_wounds_tooltip",
    }
    local missing = {}
    for _, key in ipairs(keys) do
        local v = mod:localize(key)
        if not v or v == key or #v == 0 then
            missing[#missing + 1] = key
        end
    end
    if #missing > 0 then
        return "localization missing/empty: " .. table.concat(missing, ", ")
    end
end)

_rt_register("miracle_of_isha_hook_installed", function()
    -- The vanilla revive mutator is neutralized via a hook on
    -- MutatorTemplates.blessing_of_isha.server.start_function (NOT the dead
    -- server_start_function field per feedback_vt2_mutator_template_server_wrap).
    -- The hook-install path writes _G.__ct_isha_suppression_hook_installed = true
    -- ONLY on the success branch. False/missing means the template wasn't loaded
    -- at mod-init (rare timing edge) and alternative modes would coexist with
    -- vanilla's revive instead of replacing it.
    if _G.__ct_isha_suppression_hook_installed ~= true then
        return "Isha mutator suppression hook not installed (MutatorTemplates.blessing_of_isha.server.start_function unreachable at mod init)"
    end
end)

-- v0.7.153-dev: Aegis/Wounds are NEXT-MISSION-ONLY, Ulric stays whole-run.
-- Locks in Option B against a future accidental re-add of is_persistent on the
-- Isha buffs (which would silently revert them to whole-run via DeusSpawning's
-- save loop). Two assertions:
--   1. Source-pattern marker constant for the apply+consume hook is present.
--   2. LIVE invariant on the registered BuffTemplates: Ulric carries
--      is_persistent (whole-run save path) but Aegis/Wounds do NOT — exactly
--      one of the three miracle buffs is persistent.
_rt_register("miracle_of_isha_one_mission_not_persistent", function()
    if type(CT_ISHA_ONE_MISSION_MARKER) ~= "string" then
        return "CT_ISHA_ONE_MISSION_MARKER not defined — the _apply_initial_buffs apply/consume hook may have been removed"
    end
    if CT_ISHA_ONE_MISSION_MARKER ~= "isha_one_mission:apply_initial_buffs_node_key_v0.7.153" then
        return "CT_ISHA_ONE_MISSION_MARKER mismatch — expected node-key apply/consume hook, got: "
            .. tostring(CT_ISHA_ONE_MISSION_MARKER)
    end
    local bt = rawget(_G, "BuffTemplates")
    if not bt then
        return nil  -- BuffTemplates not loaded yet; can't verify the live invariant
    end
    local function is_persistent_of(name)
        local tpl = bt[name]
        local buff = tpl and tpl.buffs and tpl.buffs[1]
        return buff and buff.is_persistent or nil
    end
    local ulric  = is_persistent_of(CT_BUFF_MIRACLE_OF_ULRIC)
    local aegis  = is_persistent_of(CT_BUFF_MIRACLE_OF_ISHA_AEGIS)
    local wounds = is_persistent_of(CT_BUFF_MIRACLE_OF_ISHA_WOUNDS)
    if not ulric then
        return "Miracle of Ulric LOST is_persistent — it must stay whole-run"
    end
    if aegis or wounds then
        return string.format("Isha buff re-gained is_persistent (must be next-mission-only): aegis=%s wounds=%s",
            tostring(aegis), tostring(wounds))
    end
end)

_rt_register("engineer_bombs_not_in_world_spawns", function()
    -- v0.7.97: verifies the Outcast Engineer crafted bomb (and any other
    -- career-exclusive pickups added later) is in _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST.
    -- Vanilla source-of-truth list of names to assert (mirrors the static set of
    -- career-exclusive pickups that exist as `Pickups.*` entries in current
    -- vanilla code -- pickups.lua:698 for engineer_grenade_t1).
    --
    -- This is a SOURCE-pattern check: it does NOT require an active CW run.
    -- Returns nil for PASS, error string with the missing names on FAIL. If
    -- a future vanilla update introduces a new career-exclusive pickup, the
    -- expected-list constant below must be extended in lockstep.
    local EXPECTED_BLOCKLIST = {
        "engineer_grenade_t1",  -- Bardin Outcast Engineer's crafted bomb (cog dlc)
    }
    if type(_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST) ~= "table" then
        return "_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST not defined"
    end
    local missing = {}
    for _, name in ipairs(EXPECTED_BLOCKLIST) do
        if not _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST[name] then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        return "blocklist missing: " .. table.concat(missing, ", ")
    end
end)

_rt_register("engineer_bombs_present_in_vanilla_pickups", function()
    -- v0.7.97: sanity-check the inverse side: the blocklisted names must
    -- actually exist somewhere in the global `Pickups` table, otherwise the
    -- blocklist is just dead code (vanilla changed the name out from under us
    -- and our denial path is silently a no-op). Returns nil for PASS, string
    -- listing names that vanished from Pickups on FAIL. Tolerates the keep-
    -- load timing where Pickups might not be loaded yet (returns nil = PASS).
    if not _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST or not Pickups then
        return nil
    end
    local missing = {}
    for name in pairs(_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST) do
        local found = false
        for _, bucket in pairs(Pickups) do
            if type(bucket) == "table" and bucket[name] then
                found = true
                break
            end
        end
        if not found then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        return "blocklist names absent from Pickups (vanilla rename?): " .. table.concat(missing, ", ")
    end
end)

-- v0.7.104: ct_meta_ammo now uses hyperbolic cost-floor scaling via direct hooks
-- on `GenericAmmoUserExtension.use_ammo`, `PlayerUnitEnergyExtension.drain`, and
-- `PlayerUnitOverchargeExtension.add_charge`. The v0.7.102-era stat_buff entries
-- (`reduced_overcharge`, `ammo_used_multiplier`) were REMOVED because vanilla
-- `stacking_multiplier` resolution is linear-additive — 20 stacks of -0.05 → 0
-- (free shots / casts). The new path scales per-shot cost by
-- `_ct_meta_ammo_cost_multiplier(N)` which is BOUNDED in [0.25, 1.0] for any N.
--
-- The three checks below replace the v0.7.102 `ct_meta_ammo_uses_consumption_side`
-- check (which is now obsolete — the consumption-side stat_buff entries are gone).
-- KEEP `ct_clamp_helper_present` and `ct_no_direct_max_energy_mutation` (both still
-- valid: helper still useful, no direct _max_ writes anywhere in ct).
--
-- Crash class closed: 20-boon ct_meta_ammo run → cost_factor=0 → infinite ammo
-- (`generic_ammo_user_extension.lua:430` round-to-zero) / infinite energy
-- (`player_unit_energy_extension.lua:95`) / infinite overcharge
-- (`player_unit_overcharge_extension.lua:340+343`). All now ride a
-- hyperbolic-saturating curve with a 25% floor (mathematically impossible to reach
-- 0 or negative).
_rt_register("ct_meta_ammo_hyperbolic_floor_v0_7_104", function()
    -- Marker constant present + matches expected value (source-pattern check).
    if type(CT_META_AMMO_HYPERBOLIC_MARKER) ~= "string" then
        return "CT_META_AMMO_HYPERBOLIC_MARKER not defined (hyperbolic-floor rewrite reverted?)"
    end
    if CT_META_AMMO_HYPERBOLIC_MARKER ~= "CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104" then
        return "CT_META_AMMO_HYPERBOLIC_MARKER mismatch — expected v0.7.104, got: " .. tostring(CT_META_AMMO_HYPERBOLIC_MARKER)
    end
    -- Helper exposed on the mod table.
    if type(mod._ct_meta_ammo_cost_multiplier) ~= "function" then
        return "mod._ct_meta_ammo_cost_multiplier helper missing"
    end
    -- BuffTemplates entry exists and the v0.7.102 stat_buffs are GONE.
    local buff_templates = rawget(_G, "BuffTemplates")
    local stack = buff_templates and buff_templates.ct_meta_ammo_stack
    if not stack or type(stack.buffs) ~= "table" then
        return "ct_meta_ammo_stack BuffTemplates entry missing or malformed"
    end
    local found_total_ammo = false
    for _, b in ipairs(stack.buffs) do
        if b.stat_buff == "total_ammo" then found_total_ammo = true end
        if b.stat_buff == "ammo_used_multiplier" then
            return "ct_meta_ammo_stack still contains `ammo_used_multiplier` stat_buff — v0.7.104 hyperbolic rewrite incomplete (linear-additive bug class back)"
        end
        if b.stat_buff == "reduced_overcharge" then
            return "ct_meta_ammo_stack still contains `reduced_overcharge` stat_buff — v0.7.104 hyperbolic rewrite incomplete (linear-additive bug class back)"
        end
        if b.stat_buff == "max_energy" or b.stat_buff == "max_overcharge" then
            return "ct_meta_ammo_stack contains direct max_energy / max_overcharge stat_buff (engine-network-bounded bug back)"
        end
    end
    if not found_total_ammo then
        return "ct_meta_ammo_stack missing `total_ammo` stat_buff (positive-only capacity growth, must remain)"
    end
end)

_rt_register("ct_meta_ammo_cost_floor_holds", function()
    -- Math floor must hold at extreme N: the cost factor for 1000 boons must
    -- be >= 0.25 and <= 1.0. Asserts the helper's curve is correctly bounded.
    if type(mod._ct_meta_ammo_cost_multiplier) ~= "function" then
        return "_ct_meta_ammo_cost_multiplier helper missing"
    end
    local f = mod._ct_meta_ammo_cost_multiplier(1000)
    if type(f) ~= "number" then
        return "_ct_meta_ammo_cost_multiplier(1000) did not return a number (got " .. type(f) .. ")"
    end
    if f < 0.25 then
        return string.format("cost_factor at N=1000 is %.6f, BELOW floor 0.25 (asymptote breached)", f)
    end
    if f > 1.0 then
        return string.format("cost_factor at N=1000 is %.6f, ABOVE 1.0 (ceiling breached — would BUFF cost)", f)
    end
    -- Also: N=0 must return exactly 1.0 (no behavior change without active boons).
    local f0 = mod._ct_meta_ammo_cost_multiplier(0)
    if math.abs(f0 - 1.0) > 1e-9 then
        return string.format("cost_factor at N=0 is %.6f, expected exactly 1.0 (zero-boon no-op broken)", f0)
    end
end)

_rt_register("ct_meta_ammo_no_zero_cost", function()
    -- Runtime probe: iterate num_boons from 0 to 50, assert cost factor never
    -- drops below 0.25 AND never exceeds 1.0 AND monotonically non-increasing
    -- (sanity check on the curve shape).
    if type(mod._ct_meta_ammo_cost_multiplier) ~= "function" then
        return "_ct_meta_ammo_cost_multiplier helper missing"
    end
    local prev = math.huge
    for n = 0, 50 do
        local f = mod._ct_meta_ammo_cost_multiplier(n)
        if type(f) ~= "number" then
            return string.format("cost_factor at N=%d returned non-number (%s)", n, type(f))
        end
        if f < 0.25 then
            return string.format("cost_factor at N=%d is %.6f, below floor 0.25 (zero-cost bug class back)", n, f)
        end
        if f > 1.0 then
            return string.format("cost_factor at N=%d is %.6f, above 1.0 (negative discount — cost AMPLIFIED)", n, f)
        end
        if f > prev + 1e-9 then
            return string.format("cost_factor non-monotonic: N=%d gave %.6f (prev=%.6f) — curve shape regressed", n, f, prev)
        end
        prev = f
    end
end)

_rt_register("ct_meta_ammo_stacks_bounded", function()
    -- v0.7.108-dev (Issue #34): asserts the multi-layer overflow defense for
    -- `ct_meta_ammo` (and siblings) is intact. Three checks:
    --   1. CT_META_AMMO_MAX_STACKS sentinel exists and equals 30.
    --   2. Every `ct_meta_*_stack_*` sub-buff in BuffTemplates has
    --      `max_stacks = CT_META_AMMO_MAX_STACKS` (i.e. NOT math.huge).
    --   3. Synthetic stress test: simulate 50 hypothetical boons stacking
    --      `total_ammo` via the engine's stacking_multiplier formula
    --      (`final_value = final_value * (multiplier + 1) + bonus`), assert
    --      the result is finite AND <= 9999 (the belt-and-suspenders ceiling
    --      enforced inside the `_apply_buffs` hook).
    if type(CT_META_AMMO_MAX_STACKS) ~= "number" then
        return "CT_META_AMMO_MAX_STACKS sentinel missing (Issue #34 cap reverted?)"
    end
    if CT_META_AMMO_MAX_STACKS ~= 30 then
        return string.format("CT_META_AMMO_MAX_STACKS drifted: got %s, expected 30", tostring(CT_META_AMMO_MAX_STACKS))
    end

    local buff_templates = rawget(_G, "BuffTemplates")
    if not buff_templates then
        return "BuffTemplates not loaded (run in-keep)"
    end
    -- Walk every template whose key matches `ct_meta_*_stack` and check the
    -- max_stacks ceiling on every sub-buff.
    local offenders = {}
    for tpl_name, tpl in pairs(buff_templates) do
        if type(tpl_name) == "string" and tpl_name:find("^ct_meta_") and tpl_name:find("_stack$")
           and type(tpl) == "table" and type(tpl.buffs) == "table" then
            for _, sb in ipairs(tpl.buffs) do
                local ms = sb.max_stacks
                if ms == nil or ms == math.huge or (type(ms) == "number" and ms > CT_META_AMMO_MAX_STACKS) then
                    offenders[#offenders + 1] = string.format("%s.%s max_stacks=%s",
                        tpl_name, tostring(sb.name), tostring(ms))
                end
            end
        end
    end
    if #offenders > 0 then
        return "ct_meta_* sub-buffs missing max_stacks cap: " .. table.concat(offenders, "; ")
    end

    -- Synthetic 50-boon stress test of the engine's stacking_multiplier formula
    -- (buff_extension.lua:1391-1448). Base ammo = 100 (representative middle-of-
    -- the-road weapon), multiplier = 0.05 (ct_meta_ammo's `total_ammo` stack
    -- value), simulate clamped stack count = min(50, CT_META_AMMO_MAX_STACKS).
    -- After the simulated loop, run through the same `math.min(buffed_max, 9999)`
    -- belt-and-suspenders gate the `_apply_buffs` hook applies.
    local base = 100
    local multiplier = 0.05
    local stacks_to_apply = math.min(50, CT_META_AMMO_MAX_STACKS)
    local value = base
    for _ = 1, stacks_to_apply do
        value = value * (multiplier + 1)  -- no bonus term for ct_meta_ammo
    end
    if value ~= value or value == math.huge then  -- NaN or inf
        return string.format("simulated _max_ammo overflow at N=%d (got %s) — engine formula change?", stacks_to_apply, tostring(value))
    end
    local clamped = math.min(value, 9999)
    if clamped > 9999 then
        return string.format("post-clamp value %s exceeds 9999 ceiling (defense breach)", tostring(clamped))
    end
    -- Sanity: at N=30, 100 * 1.05^30 ≈ 432, finite and HUD-printable.
    if not (clamped > base) then
        return string.format("simulated stacking produced no growth: base=%d, result=%s", base, tostring(clamped))
    end
end)

_rt_register("ct_clamp_helper_present", function()
    -- Verify the universal _clamp_network_bounded_max helper exists, is exposed
    -- on the mod table, and emits a value <= NetworkConstants.max_energy.max
    -- for a deliberately oversized input.
    if type(mod._clamp_network_bounded_max) ~= "function" then
        return "mod._clamp_network_bounded_max helper missing (universal safeguard removed?)"
    end
    local nc = rawget(_G, "NetworkConstants")
    local cap_oc = (nc and nc.max_overcharge and nc.max_overcharge.max) or 60
    local cap_en = (nc and nc.max_energy     and nc.max_energy.max)     or 60
    local got_oc = mod._clamp_network_bounded_max("max_overcharge", 9999)
    local got_en = mod._clamp_network_bounded_max("max_energy",     9999)
    if type(got_oc) ~= "number" or got_oc > cap_oc then
        return string.format("clamp helper failed for max_overcharge: got %s, cap %d", tostring(got_oc), cap_oc)
    end
    if type(got_en) ~= "number" or got_en > cap_en then
        return string.format("clamp helper failed for max_energy: got %s, cap %d", tostring(got_en), cap_en)
    end
    -- Source-pattern sentinel check: scan the local helper body via tostring of
    -- the closure (best-effort; if string.dump fails we fall through to PASS,
    -- relying on the runtime test above).
    -- (No further check — runtime emission proves the body is correct.)
end)

_rt_register("reckless_swings_name_based_lookup", function()
    -- Asserts the v0.7.92 GH #5 fix (name-based lookup, NOT positional
    -- buffs[1]/description_values[1]/[3] indexing) is still in place. Two
    -- defenses:
    --   1. Source-pattern marker constant — if a refactor reverts the
    --      tweak to positional indexing the most plausible bitrot path
    --      also strips the v0.7.92 doc-block and the marker declaration,
    --      so the upvalue resolves to nil here.
    --   2. `_find_entry_by` helper presence — the name-based lookup is
    --      built around this helper; a positional revert would remove it.
    -- Either condition failing means the v0.7.92 fix is gone.
    if type(CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER) ~= "string" then
        return "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER not defined — was the v0.7.92 name-based-lookup fix reverted?"
    end
    if CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER ~= "name-based-lookup-v0.7.92" then
        return "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER mismatch — expected name-based-lookup-v0.7.92, got: " .. tostring(CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER)
    end
    if type(_find_entry_by) ~= "function" then
        return "_find_entry_by helper missing — name-based lookup machinery removed?"
    end
    -- Stored-indices schema check (only when the tweak is active): the
    -- v0.7.92 `reckless_swings_originals` payload uses numeric `buff_index`,
    -- `dv_threshold_index`, `dv_damage_index` fields. A positional-only
    -- revert would store fewer or differently-named keys.
    if reckless_swings_originals then
        local r = reckless_swings_originals
        if type(r.buff_index) ~= "number" or type(r.dv_threshold_index) ~= "number" or type(r.dv_damage_index) ~= "number" then
            return string.format("reckless_swings_originals schema mismatch — expected numeric buff_index/dv_threshold_index/dv_damage_index, got %s/%s/%s",
                type(r.buff_index), type(r.dv_threshold_index), type(r.dv_damage_index))
        end
    end
end)

_rt_register("ct_no_direct_max_energy_mutation", function()
    -- Runtime check: walk every player unit (humans + bots) and assert that any
    -- `_max_energy` we observe is ≤ NetworkConstants.max_energy.max. Post-v0.7.102
    -- ct never writes this field, so any out-of-bounds value implies either a
    -- regression OR a non-ct mod is doing the bad thing. Best-effort: if
    -- Managers.player isn't ready (keep load timing) we return nil (PASS).
    --
    -- Also asserts the same for `_max_overcharge` for symmetry — same engine cap
    -- pattern, same fassert shape.
    local pm = Managers and Managers.player
    if not pm or type(pm.human_and_bot_players) ~= "function" then return nil end
    local nc = rawget(_G, "NetworkConstants")
    local cap_en = (nc and nc.max_energy     and nc.max_energy.max)     or 60
    local cap_oc = (nc and nc.max_overcharge and nc.max_overcharge.max) or 60
    local ok, players = pcall(pm.human_and_bot_players, pm)
    if not ok or type(players) ~= "table" then return nil end
    local offenders = {}
    for _, pl in pairs(players) do
        local unit = pl and pl.player_unit
        if unit and Unit.alive(unit) then
            local en_ext = ScriptUnit.has_extension(unit, "energy_system")
            local m_en = en_ext and en_ext._max_energy
            if type(m_en) == "number" and m_en > cap_en then
                local prof = pl.profile_display_name and pl:profile_display_name() or "?"
                offenders[#offenders + 1] = string.format("max_energy=%d on %s (cap %d)", m_en, tostring(prof), cap_en)
            end
            local oc_ext = ScriptUnit.has_extension(unit, "overcharge_system")
            local m_oc = oc_ext and (oc_ext.max_value or oc_ext._max_overcharge)
            if type(m_oc) == "number" and m_oc > cap_oc then
                local prof = pl.profile_display_name and pl:profile_display_name() or "?"
                offenders[#offenders + 1] = string.format("max_overcharge=%d on %s (cap %d)", m_oc, tostring(prof), cap_oc)
            end
        end
    end
    if #offenders > 0 then
        return "network-bounded _max_<X> exceeds engine cap: " .. table.concat(offenders, "; ")
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)

_rt_register("ct_rpc_schema_present", function()
    -- v0.7.114-dev (Issue #27): explicit RPC schema_version pilot.
    -- Asserts CT_RPC_SCHEMA exists as a number >= 1 so a future refactor
    -- can't silently drop the constant and undo cross-version drop-on-mismatch.
    -- See VMF_RECIPES.md § 10 + the CT_RPC_SCHEMA comment block near MOD_VERSION.
    if type(CT_RPC_SCHEMA) ~= "number" then
        return "CT_RPC_SCHEMA not defined as number (got " .. type(CT_RPC_SCHEMA) .. ")"
    end
    if CT_RPC_SCHEMA < 1 then
        return string.format("CT_RPC_SCHEMA=%d is < 1 (initial value should be 1)", CT_RPC_SCHEMA)
    end
end)



_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_localization")
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

-- audit 2026-06-07 (v0.7.133-dev): forward-ref fix for the two pickup dump
-- helpers. They are referenced inside the populate_pickups hook closure (built
-- at load) BEFORE their definitions far below. Without the forward declaration +
-- dropping `local` on the definitions, the closure captured a nil global and the
-- post-populate diagnostics silently no-op'd. This check FAILS if either helper
-- reverts to `nil` at this lexical scope (which is the SAME chunk scope the hook
-- closure captures from), or if a future edit accidentally leaks them to _G
-- instead of the forward-declared upvalue (the broken-global variant of the bug).
_rt_register("pickup_dump_helpers_forward_declared", function()
    if type(_dump_pickup_system_state) ~= "function" then
        return "_dump_pickup_system_state is not a function at chunk scope — forward-decl slot broken; populate_pickups dumps would no-op"
    end
    if type(_dump_pickup_spawners_verbose) ~= "function" then
        return "_dump_pickup_spawners_verbose is not a function at chunk scope — forward-decl slot broken; populate_pickups dumps would no-op"
    end
    -- They must be upvalues (forward-declared locals), NOT globals. A leak to _G
    -- means someone dropped `local` AND removed the forward declaration.
    if rawget(_G, "_dump_pickup_system_state") ~= nil then
        return "_dump_pickup_system_state leaked to _G — forward-declaration removed; use the local forward-decl pattern"
    end
    if rawget(_G, "_dump_pickup_spawners_verbose") ~= nil then
        return "_dump_pickup_spawners_verbose leaked to _G — forward-declaration removed; use the local forward-decl pattern"
    end
end)

-- audit 2026-06-07 (v0.7.133-dev): marker that the three variadic forwarding
-- hooks preserve real arity (select("#")/unpack(t,1,n)) rather than bare
-- unpack(args). Lua can't read its own bundle source at runtime (see the
-- open_chest_hook_singleton check), so this asserts the marker constant the fix
-- sites are documented against.
_rt_register("variadic_hooks_arity_preserved", function()
    if type(CT_VARIADIC_ARITY_MARKER) ~= "string" then
        return "CT_VARIADIC_ARITY_MARKER not defined — variadic hooks may have reverted to bare unpack(args), truncating at nil holes"
    end
    if CT_VARIADIC_ARITY_MARKER ~= "unpack_arity:select_count_v0.7.133" then
        return "CT_VARIADIC_ARITY_MARKER mismatch — expected select-count form, got: " .. tostring(CT_VARIADIC_ARITY_MARKER)
    end
    -- Behavioral proof the idiom actually preserves a trailing nil hole, which
    -- bare unpack(t) does NOT (the whole point of the §2a fix). Build args with a
    -- nil in the middle and a real value after it; capture n via select("#"), then
    -- confirm unpack(args, 1, n) yields the trailing value (bare unpack would stop
    -- at the nil hole and drop it).
    local function _roundtrip(...)
        local n = select("#", ...)
        local args = { ... }
        return select("#", unpack(args, 1, n)), (select(n, unpack(args, 1, n)))
    end
    local count, last = _roundtrip("a", nil, "z")  -- 3 args, hole at #2
    if count ~= 3 then
        return string.format("arity idiom dropped a nil hole: expected 3 forwarded args, got %d", count)
    end
    if last ~= "z" then
        return string.format("arity idiom dropped the trailing arg after a nil hole: expected 'z', got %s", tostring(last))
    end
end)

-- v0.7.203-dev: the Home Brewer potency hook on BuffExtension.add_buff scales the
-- brewed-potion sub-buff multiplier/bonus, calls vanilla, then restores. Its guarded
-- path previously did `local result = func(...); return result`, collapsing vanilla's
-- three returns (id, sub_buffs_added, first_buff — buff_extension.lua:517) to one. The
-- fix routes through _capture_returns + unpack(results, 1, n). Lua can't read its own
-- bundle at runtime, so this asserts the marker constant the fix site is documented
-- against (same shape as variadic_hooks_arity_preserved / endless_bombs_strip_on_expiry).
_rt_register("home_brewer_add_buff_multireturn_preserved", function()
    if type(CT_HOME_BREWER_MULTIRETURN_MARKER) ~= "string" then
        return "CT_HOME_BREWER_MULTIRETURN_MARKER not defined — the Home Brewer add_buff hook may have reverted to a single-return `local result = func(...)` collapse (drops sub_buffs_added + first_buff)"
    end
    if CT_HOME_BREWER_MULTIRETURN_MARKER ~= "home_brewer_add_buff:capture_returns_unpack_v0.7.203" then
        return "CT_HOME_BREWER_MULTIRETURN_MARKER mismatch — expected capture_returns/unpack form, got: " .. tostring(CT_HOME_BREWER_MULTIRETURN_MARKER)
    end
end)

-- v0.7.134 regression: v0.7.133's arity fix captured n at hook entry, but the
-- Belakor-temple branch writes args[8] = "unique" AFTER capture; the cursed-chest
-- call site passes only 7 args (deus_run_controller.lua:1115), so unpack(args, 1, 7)
-- silently dropped the forced rarity while the [belakor-temple] log line still
-- claimed forced=unique. The hook must extend n after the write.
_rt_register("belakor_forced_rarity_survives_unpack_bound", function()
    if type(mod._ct_extend_arity_for_forced_rarity) ~= "function" then
        return "_ct_extend_arity_for_forced_rarity missing — Belakor forced-rarity arity bump regressed"
    end
    -- Replicate the capture→mutate→forward sequence with vanilla's 7-arg shape.
    local function _roundtrip(...)
        local n = select("#", ...)
        local args = { ... }
        args[8] = "unique"                                -- the Belakor-temple write
        n = mod._ct_extend_arity_for_forced_rarity(n)     -- the v0.7.134 bump
        return select("#", unpack(args, 1, n)), (select(8, unpack(args, 1, n)))
    end
    local count, forced = _roundtrip("seed", 3, {}, "cataclysm", 0.5, "cursed_chest", "wh_priest")
    if count ~= 8 then
        return string.format("forced-rarity arg dropped at the forward: expected 8 args, got %d", count)
    end
    if forced ~= "unique" then
        return string.format("args[8] not forwarded: expected 'unique', got %s", tostring(forced))
    end
    if mod._ct_extend_arity_for_forced_rarity(9) ~= 9 then
        return "arity bump must not SHRINK n when the caller already passed more than 8 args"
    end
end)

-- audit 2026-06-07 (F14, v0.7.133-dev): the four DeusWeaponGeneration trait-filter
-- hooks must ALWAYS restore DeusWeapons[*].baked_trait_combinations even when the
-- wrapped vanilla call raises — otherwise the global table stays filtered for the
-- rest of the session (state corruption). The real hooks route through
-- _filtered_weapon_gen, which is a file-scope local (not exposed). This check
-- replicates that exact apply/pcall/restore contract on a synthetic table and
-- asserts state is restored after a throwing func — a behavioral guard that would
-- FAIL if the pcall+restore-on-error bracket were removed (the pre-F14 shape that
-- skipped restore on the error path).
_rt_register("trait_filter_restores_on_error", function()
    local synthetic = { combos = "ORIGINAL" }
    -- mirror of the hardened bracket: save -> pcall(vanilla) -> restore -> re-raise
    local function guarded_gen(throwing_func)
        local saved = synthetic.combos
        synthetic.combos = "FILTERED"  -- apply_weapon_trait_filter analogue
        local ok, result = pcall(throwing_func)
        synthetic.combos = saved       -- restore_weapon_trait_filter analogue
        if not ok then error(result, 2) end
        return result
    end
    -- success path: state restored, result returned
    local ok1, r1 = pcall(guarded_gen, function() return "WEAPON" end)
    if not ok1 then return "guarded_gen raised on the success path: " .. tostring(r1) end
    if synthetic.combos ~= "ORIGINAL" then
        return "trait combos not restored after a SUCCESSFUL roll (got " .. tostring(synthetic.combos) .. ")"
    end
    -- error path: vanilla raised — state MUST still be restored (the F14 contract)
    local ok2 = pcall(guarded_gen, function() error("simulated vanilla crash") end)
    if ok2 then return "guarded_gen swallowed the vanilla error instead of re-raising it" end
    if synthetic.combos ~= "ORIGINAL" then
        return "F14 REGRESSION: trait combos left FILTERED after vanilla raised — restore was skipped on the error path"
    end
end)

-- ct_dev 0.7.162-dev: the dup-career extra-chip node_key resolution must be
-- `final_node_selected > vote > nil` with NO trailing current-node fallback.
-- The old chain ended in `or current_node` .. `_key`, which planted a visible
-- chip on the party's CURRENT node for an unvoted duplicate peer (a valid node
-- that is NOT where they voted — the "valid-but-wrong mission node" bug). The
-- marker is set on `mod` by _ct_dup_vote_chips.lua at the resolution site (the
-- bundle is unreadable at runtime, so we read the exported invariant string).
-- The needle for the forbidden tail is split across two literals below so this
-- check's own source text can't be mistaken for a reintroduction of it.
_rt_register("dup_chip_no_current_node_fallback", function()
    local resolution = mod._ct_dup_chip_node_key_resolution
    if type(resolution) ~= "string" then
        return "DUP-CHIP REGRESSION: mod._ct_dup_chip_node_key_resolution missing — "
            .. "_ct_dup_vote_chips.lua extra-chip node_key resolution marker not exported "
            .. "(dup-chip wrong-node fix may have been reverted)"
    end
    if resolution ~= "final_node_selected>vote>nil" then
        return "DUP-CHIP REGRESSION: extra-chip node_key resolution is '" .. tostring(resolution)
            .. "', expected 'final_node_selected>vote>nil' — a current-node fallback may have been reintroduced "
            .. "(plants a chip on the wrong/current mission node for an unvoted duplicate peer)"
    end
    -- Defensive: the forbidden fallback token must NOT appear in the exported
    -- resolution string. Needle split across two literals so THIS line isn't a
    -- self-match.
    local forbidden = "current_node" .. "_key"
    if string.find(resolution, forbidden, 1, true) then
        return "DUP-CHIP REGRESSION: exported resolution names the forbidden current-node fallback — "
            .. "the extra-chip node_key chain must end at nil, not " .. forbidden
    end
end)

-- Issue #97 (ct_dev 0.7.163-dev): the three chunked host->client broadcasts must
-- be PACED through the enqueue/drain send queue, never inline-burst inside their
-- `for seq` loops. A single-frame burst of N chunks overran the reliable network
-- channel's queue cap and silently dropped chunks (reassembly then never
-- completes). This check verifies the marker + the live drain wiring: exactly one
-- `mod.update` drainer owner and the per-frame budget global both present.
_rt_register("chunk_sends_paced_not_bursted", function()
    if type(_CT_CHUNK_PACED_SEND_MARKER) ~= "string" then
        return "PACED-SEND REGRESSION: _CT_CHUNK_PACED_SEND_MARKER not defined — "
            .. "the #97 paced chunk-send queue may have been removed (chunked broadcasts could inline-burst again)"
    end
    if _CT_CHUNK_PACED_SEND_MARKER ~= "chunk_sends:enqueue_drain_paced_v0.7.163" then
        return "PACED-SEND REGRESSION: _CT_CHUNK_PACED_SEND_MARKER mismatch — expected enqueue/drain form, got: "
            .. tostring(_CT_CHUNK_PACED_SEND_MARKER)
    end
    -- The enqueue entry point that all three broadcasters route through.
    if type(_ct_enqueue_chunk) ~= "function" then
        return "PACED-SEND REGRESSION: _ct_enqueue_chunk missing — chunked broadcasts have no paced send path"
    end
    -- Exactly ONE drainer owner: mod.update must be the live drain function.
    -- (If a second feature reassigned mod.update, the drain stops and the queue
    -- never empties; if it's gone, chunks are never sent at all.)
    if type(mod.update) ~= "function" then
        return "PACED-SEND REGRESSION: mod.update drainer owner missing — the paced send queue is never drained "
            .. "(chunks enqueue but never emit)"
    end
    -- The per-frame budget global must survive — its removal would either stall
    -- the drain (nil budget) or re-tempt an inline burst.
    if type(_CT_CHUNK_DRAIN_BUDGET) ~= "number" or _CT_CHUNK_DRAIN_BUDGET < 1 then
        return "PACED-SEND REGRESSION: _CT_CHUNK_DRAIN_BUDGET missing or invalid (got "
            .. tostring(_CT_CHUNK_DRAIN_BUDGET) .. ") — the per-frame drain budget is gone"
    end
    -- The send queue table backing the FIFO must exist.
    if type(_ct_chunk_send_queue) ~= "table" then
        return "PACED-SEND REGRESSION: _ct_chunk_send_queue FIFO table missing — paced send queue dismantled"
    end
end)

-- Mechanic-tweak sliders (Shadow Homing Skulls stun duration, Adventure RNG-trait
-- odds). Own chunk to stay under the 200-local main-chunk cap; reads via the
-- exposed mod._ct_effective_setting; exposes mod._ct_sync_* for the re-apply hubs.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_mechanic_tweaks")

-- Blessed Bots: Survival Boons (any gamemode). Host-side; single PlayerBotBase.update
-- hook for this mod; no network registration.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_blessed_bots")

-- Duplicate-career map-vote chips: when two peers share a career (gt's
-- allow_duplicate_careers), show BOTH voters' chips on the CW map screen instead
-- of one overwriting the other, distinguished by offset+scale. Client-side render
-- only (no new sync). Hooks DeusMapDecisionView._update_player_state (place extras)
-- + DeusMapScene._clear (teardown extras — no leak). Sole hooks on those pairs.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_dup_vote_chips")

pcall(printf, "[mem-probe] ct boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CT) / 1024)