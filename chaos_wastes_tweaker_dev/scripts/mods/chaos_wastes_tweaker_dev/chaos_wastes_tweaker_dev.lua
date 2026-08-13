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

local MOD_VERSION = "0.7.340-dev"
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

-- #357 uses one owner-targeted VMF event and client-local BuffTemplates. Keeping
-- this on `mod` avoids another file-chunk local near Lua 5.1's 200-local limit.
mod._ct_bomb_cooldown_display = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_bomb_cooldown_display")
mod._ct_bomb_cooldown_display.install(CT_RPC_SCHEMA)

-- #221: attach instead of introducing another file-chunk local; this main file
-- is already at Lua 5.1's 200-local limit.
mod._ct_umbrella_policy = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_umbrella_policy")

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- `_dbg` is for confirmation / expected behavior — mod:debug (file only,
-- gated by VMF output_mode_debug).
-- `_dbg_alert` is for unexpected / wrong / mismatch — LOG-ONLY via
-- pcall-guarded engine printf (#427/issue 240: mod:warning posts to CHAT
-- under VMF defaults - logging.lua warning mode 3, send_to_chat = mode >= 2;
-- printf always lands in console-*.log, even with mod logging OFF, and never
-- in chat; pcall so a format slip never faults the caller).
local function _dbg(fmt, ...)
    mod:debug("[ct:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[ct:dbg] " .. fmt, ...) then
        pcall(printf, "[ct:dbg] (alert format error: %s)", tostring(fmt))
    end
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

-- 2026-05-23 v0.7.100-dev: the 9 vanilla dormant boons + the Skulls event boons are purged from
-- the active code path after recurring Chest-of-Trials crashes (GUID 4c5d2157 at line 1144 -
-- the v0.7.99 half-fix left `DORMANT_BOON_RARITY` an empty table on _G while closures still
-- indexed it). The original implementation lives in block comments; re-enable is a literal
-- uncomment, but restoration needs the CW Wastes engine-level crash investigation closed first.
-- ct_kill_heal is deliberately NOT in this list: it was RE-ENABLED in v0.7.240-dev (#406) and
-- registers unconditionally in `_ct_meta_trait_boons.lua`. The ground truth these names are
-- asserted against lives with the checks in `_ct_regression.lua` (#1156, PROJECT_STANDARDS 5.1d).
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
}
local CT_DISABLED_SKULLS_BOON_NAMES = {
    "boon_skulls_01", "boon_skulls_02", "boon_skulls_03", "boon_skulls_04", "boon_skulls_05",
    "boon_skulls_06", "boon_skulls_07", "boon_skulls_08",
    "boon_skulls_set_bonus_01", "boon_skulls_set_bonus_02",
}
pcall(printf, "[ct] dormant/skulls boons purged (v%s, sentinel=%s); %d dormants + %d skulls boons removed from active code path. See comments near L4448/L4724/L5698 in source for re-enable instructions.",
    MOD_VERSION, CT_DORMANT_PURGE_VERIFIED, #CT_DISABLED_DORMANT_BOON_NAMES, #CT_DISABLED_SKULLS_BOON_NAMES)

-- /regression_test scaffold. See the corresponding _rt_register calls at end of file. Each
-- check returns nil for PASS, a `skip:`-prefixed reason for SKIP, any other string for FAIL.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
-- Feature modules loaded near EOF cannot add another main-chunk local (CT sits at
-- Lua 5.1's 200-local ceiling). Expose the existing registrar without creating a
-- second registry or callback owner.
mod._ct_rt_register = _rt_register
-- #1156 / 5.1d rule 2: a check that cannot run in the CURRENT context (keep-only globals read
-- mid-mission) returns a reason prefixed `skip:` and scores SKIP, not FAIL; wrong context in the
-- fail count is what scored a mid-mission run FAIL on healthy code (anath_raema_registry_retry_
-- 288, 2026-08-04). A skip is never a pass. et/cosmetics express this as a registration-time
-- opts.precondition (#512); ct returns it because its entry is at its ceiling - unify later.
mod:command("ct_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail, skip = 0, 0, 0
    mod:echo("=== ct regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            _dbg("[regression] PASS %s", c.name)
        elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
            local why = err:sub(6):gsub("^%s+", "")
            mod:echo("  SKIP: %s -- %s", c.name, why); skip = skip + 1
            pcall(printf, "[regression] SKIP %s: %s", c.name, why)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
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
mod._ct_starting_coins_policy = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_starting_coins_policy")

-- #487 freeze diagnostics. Stored on mod._ (not a new top-level local) to stay
-- under Lua 5.1's 200-local chunk ceiling. Loaded here (after _adventure_pool,
-- before mod.update and the DeusRunController.setup_run hook - its only callers)
-- so the pool-snapshot helper can read the LIVE LEVEL_AVAILABILITY the deus
-- solver consumes. Instrumentation only; see _ct_diag_freeze487.lua header.
mod._ct_freeze487 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_freeze487")

-- #132 Chest-of-Trials over-spawn diagnostic. Stored on mod._ (not a new top-
-- level local) to stay under Lua 5.1's 200-local chunk ceiling. Its only caller
-- is the DeusCursedChestExtension.extensions_ready hook below; see the module
-- header for why this seam (spawn-path-independent ground truth) is not covered
-- by the existing [ct-probe]/[ct-spawn-tally] count probes.
mod._ct_chest132 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132")

-- #52 Tower of Treachery skull diagnostics. Stored on mod._ to keep the
-- GameModeHelper hook below small and to keep the source-backed finding in one
-- place: Tower skulls are level-flow interactables, not the portals
-- `gargoyle_head` pickup path. See _ct_diag_skull52.lua.
mod._ct_diag_skull52 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_skull52")
pcall(mod._ct_diag_skull52.install)
_rt_register("issue52_skull_diag_installed", mod._ct_diag_skull52.regression)

-- #505 Single Mission Loader. Registers /ct_load_mission + friends and the
-- ct_dev_load_selected_mission menu keybind target. No hooks - it forces a run via
-- vanilla's DeusMechanism:debug_load_deus_level + script_data overrides, so there
-- is no (Class, method) to collide with. Loaded here (after _adventure_pool so the
-- catalog can read the LIVE, injected LEVEL_AVAILABILITY for /ct_list_missions).
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission")
-- Regression guard: the loader module + its menu keybind target must survive any
-- future refactor (the whole verification lever depends on them being callable).
_rt_register("single_mission_loader_redesign_505", function()
    if not mod._ct_dev_mission_loaded then return "single-mission loader module did not load" end
    if type(mod.ct_dev_load_selected_mission) ~= "function" then return "ct_dev_load_selected_mission keybind target missing" end
    if type(mod._ct_dev_mission_do_load) ~= "function" then return "single-mission load primitive missing" end
    if type(mod._ct505_in_pilgrimage_chamber) ~= "function" then return "Pilgrimage Chamber gate helper missing" end
    if not mod._ct505_in_pilgrimage_chamber("morris_hub") or mod._ct505_in_pilgrimage_chamber("inn_level") then
        return "Pilgrimage Chamber gate must accept only morris_hub"
    end
    local cat = mod._ct_dev_mission_catalog
    if type(cat) ~= "table" or type(cat.compose_level_key) ~= "function" then return "mission catalog/composer missing" end
    if not (cat.sanitize_progress and cat.MAX_RUN_PROGRESS == 0.999 and cat.PROGRESS[#cat.PROGRESS] == 0.999 and cat.sanitize_progress(1) == 0.999) then return "unsafe run progress" end
    if type(cat.MISSIONS) ~= "table" or #cat.MISSIONS <= #AdventurePool.CW_SCENARIOS then
        return "mission catalog does not include Adventure plus CW missions"
    end
    local required = { [cat.CATEGORY_HELMGART] = false, [cat.CATEGORY_DLC] = false, [cat.CATEGORY_CW] = false }
    for _, mission in ipairs(cat.MISSIONS) do if required[mission.category] ~= nil then required[mission.category] = true end end
    for category, present in pairs(required) do if not present then return "mission category missing: " .. tostring(category) end end
    local key, theme, path = cat.compose_level_key("pat_forest", "curse_rotten_miasma", { pat_forest = { paths = { 3 } } })
    if key ~= "pat_forest_nurgle_path3" or theme ~= "nurgle" or path ~= 3 then return "curse/theme/valid-path composition mismatch" end
    local widget = cat.build_menu_group()
    local ids = {}
    for _, child in ipairs(widget.sub_widgets or {}) do ids[child.setting_id] = true end
    if ids.ctdm_theme or ids.ctdm_path or ids.ctdm_blessing then return "removed theme/path/blessing selector returned" end
    if not (ids.ctdm_base and ids.ctdm_curse and ids.ctdm_progress) then return "required mission/curse/progress selectors missing" end
    if not mod._ct505_uses_starting_boons then return "loader is not wired to existing Starting Boons selections" end
    return nil
end)

-- #457 availability-model wiring guard (non-destructive; reads catalog + builders only,
-- never mutates live pool state). Catches the silent regressions the group-master revamp
-- can introduce: a mission with no owning group (would never enable), a master widget
-- missing its enable_group_ setting_id, or a generated setting_id with no localization
-- (renders a <key> marker in the menu).
_rt_register("mission_availability_groups_457", function()
    if type(AdventurePool.group_enabled) ~= "function" then return "group_enabled missing" end
    -- Every adventure/event mission must map to a known group with a single-ness flag.
    for _, m in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        local gid = AdventurePool.GROUP_ID_BY_KEY[m.key]
        if not gid then return "mission '" .. tostring(m.key) .. "' has no group id" end
        if AdventurePool.GROUP_IS_SINGLE[gid] == nil then return "group '" .. tostring(gid) .. "' missing single-ness flag" end
    end
    -- Builders must yield master checkboxes named enable_group_*, and multi-mission
    -- masters must nest an advanced_*_group. Loc must resolve for every generated id.
    local loc = AdventurePool.build_loc_entries()
    local function check_master(w, expect_advanced)
        if type(w) ~= "table" or w.type ~= "checkbox" then return "master widget not a checkbox" end
        if type(w.setting_id) ~= "string" or w.setting_id:find("^enable_group_") ~= 1 then
            return "master setting_id not enable_group_*: " .. tostring(w.setting_id)
        end
        if not loc[w.setting_id] then return "no loc for master " .. w.setting_id end
        local sub = w.sub_widgets and w.sub_widgets[1]
        if expect_advanced then
            if not (sub and sub.type == "group" and tostring(sub.setting_id):find("^advanced_") == 1) then
                return "expected advanced_*_group under " .. w.setting_id
            end
            if not loc[sub.setting_id] then return "no loc for advanced group " .. tostring(sub.setting_id) end
        end
        return nil
    end
    local cw_err = check_master(AdventurePool.build_cw_scenarios_block(), #AdventurePool.CW_SCENARIOS > 1)
    if cw_err then return "cw block: " .. cw_err end
    local ev_err = check_master(AdventurePool.build_event_missions_block(), #AdventurePool.EVENT_MISSIONS > 1)
    if ev_err then return "event block: " .. ev_err end
    for _, w in ipairs(AdventurePool.build_campaign_dlc_group_widgets()) do
        local gid = tostring(w.setting_id):gsub("^enable_group_", "")
        local err = check_master(w, not AdventurePool.GROUP_IS_SINGLE[gid])
        if err then return "campaign master '" .. tostring(w.setting_id) .. "': " .. err end
    end
    return nil
end)

-- #487 pool-floor UNDERFLOW POLICY guard. The floor must fill a short TRAVEL/SIGNATURE
-- pool by DUPLICATING the user's ENABLED missions (so a run repeats them), and a pool
-- with ZERO enabled missions must fall back to VANILLA contents - NOT backfill a single
-- disabled vanilla level (the old enforce_pool_floor behavior that surfaced arenas /
-- random maps in the user's test). Asserts the pure classifier contract at runtime;
-- no live pool state is touched.
_rt_register("pool_floor_underflow_duplicates_487", function()
    local cpf = AdventurePool.classify_pool_floor
    if type(cpf) ~= "function" then return "classify_pool_floor missing (underflow policy not exposed)" end
    if not AdventurePool.POOL_NOTICE_LOG_ONLY then
        return "pool-floor startup notices are not marked log-only (issue 570)"
    end
    if cpf(0) ~= "fallback" then
        return "0 enabled must be 'fallback' (vanilla, not disabled-backfill), got " .. tostring(cpf(0))
    end
    if cpf(1) ~= "duplicate" then
        return "1 enabled must be 'duplicate' (repeat enabled), got " .. tostring(cpf(1))
    end
    local thr = AdventurePool.POOL_SAFETY_THRESHOLD
    if type(thr) ~= "number" or thr < 6 then
        return "POOL_SAFETY_THRESHOLD must be a number >= 6 (baked-journey max node_label bound, #487; TRAVEL labels reach 6 in journey_citadel), got " .. tostring(thr)
    end
    if cpf(thr - 1) ~= "duplicate" then return "threshold-1 must still be 'duplicate'" end
    if cpf(thr) ~= "ok" then return "threshold enabled must be 'ok' (no over-duplication)" end
    if type(AdventurePool.map_duplicate_level_aliases) ~= "function" then
        return "map_duplicate_level_aliases missing (#590 network lookup budget)"
    end
    local fake_config = { LEVEL_ALIAS = {} }
    local mapped = AdventurePool.map_duplicate_level_aliases(fake_config, "ground_zero_dup1", {
        base_level_name = "ground_zero",
        paths = { 1 },
    })
    if mapped ~= 6 then return "duplicate alias did not map all six themes" end
    if fake_config.LEVEL_ALIAS.ground_zero_belakor_path1 ~= nil then
        return "duplicate alias mapper overwrote a source permutation"
    end
    if fake_config.LEVEL_ALIAS.ground_zero_dup1_belakor_path1 ~= "ground_zero_belakor_path1" then
        return "duplicate alias did not collapse to its registered source permutation"
    end
    return nil
end)

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

-- Records which run consumed the exact Starting Coins baseline. The setter is
-- itself idempotent: every setup replay replaces vanilla's argument before the
-- engine writes it, so suppressing a replay would re-admit rollover currency.
local _starting_coins_applied_for_run = nil
local STARTING_COINS_MODE_MARKER = mod._ct_starting_coins_policy.MARKER

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

-- v0.7.211-dev #102 DECOUPLE: keep-lit visual decoupled from reward rarity. The old v0.7.158
-- _setup_rarity rarity-bump was REMOVED (it climbed the reward tier on reuse); instead a re-armed
-- upgrade altar stays lit + usable via relaxed update_upgrade_chest_color / can_be_unlocked gates
-- (`<=` -> strict `<`), so the reward never climbs. Source-pattern verified by /ct_regression_test
-- check `upgrade_altar_rarity_decouple`.
-- (Global, not a main-chunk local: see note on CT_ALTAR_VISUAL_PROBE_MARKER above.)
CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER = "upgrade_altar_rarity_decouple:relaxed_gates_no_bump_v0.7.211"

-- Chest of Trials uniqueness (Task B, #117 + #463). ALWAYS-ON as of v0.7.177-dev
-- (the prior `cursed_chest_unique_trials` toggle was removed). Three host-
-- authoritative layers make consecutive Chests of Trials in one mission roll
-- different trials: (1) a per-mission activation counter mixed into the seed
-- passed to ConflictDirector.start_terror_event (varies the sub-challenge walk),
-- (2) a TerrorEventMixer.start_event wrapper that force-rotates each
-- cursed_chest_prototype inject_event block's event_name_list to a single pick
-- that DIFFERS from that block's previous pick (rotates the top-level FACTION
-- challenge), and (3, #463) the same wrapper also force-rotates each faction
-- challenge's `weighted_event_names` so the SPECIFIC trial the player sees
-- (e.g. the gas-rat / poison_wind_globadier wave) differs from that block's last
-- pick. Layer 2 alone can't stop a repeat because every CW conflict director has
-- only two factions and a chest is faction-gated to exactly one that fires, so
-- the same faction recurs every other chest and the seed-only sub-pick collides.
-- Source-pattern verified by /ct_regression_test check `cursed_chest_unique_trials`.
-- (Global, not a main-chunk local: see note on CT_ALTAR_VISUAL_PROBE_MARKER above.)
CT_COT_UNIQUE_TRIALS_MARKER = "cot_unique_trials:force_rotate_event_name_list_and_weighted_v0.7.246"
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
-- They are first REFERENCED by the consolidated PickupSystem.populate_pickups hook
-- (since v0.7.332-dev in _ct_pickup_population_owner.lua, which takes both as
-- late-binding ctx wrappers over THESE slots because it installs ABOVE the point
-- where they are filled), but their bodies live far below. Lua 5.1 binds locals
-- lexically at closure-creation time with no hoisting, so without these stubs the
-- hook closure captured the GLOBAL name (nil), `pcall(nil, ...)` returned false and
-- the dumps never fired (BUG_CLASSES §6; feedback_lua_forward_reference.md).
-- v0.7.333-dev (#1159): the bodies moved to _ct_level_load_owner.lua, which
-- re-declares the same forward slots at ITS chunk scope so both `function _name(...)`
-- lines stayed byte-identical. These two entry slots are filled from that owner's
-- exports at its install site below; _ct_regression then binds them BY VALUE from
-- a site further down, and its pickup_dump_helpers_forward_declared check catches
-- a slot left nil or leaked to _G.
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

-- #466 independent bot economy. Bot progression uses the host's DeusRunState
-- (bots are host-owned local-player rows), so existing vanilla SharedState fields
-- provide a separate balance per bot without a new network protocol.
CT_BOT_ECONOMY_MARKER = "bot_economy:independent_charge_gate_v0.7.278"
mod._ct_bot_economy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_economy")
mod._ct_bot_economy_log_count = 0
mod._ct_bot_economy_initialized = {}

-- #467 observation-only baseline for a future curated boon price/tier manifest.
-- Vanilla prices shrine boons solely by rarity, so changing an individual value
-- safely requires coordinated UI, purchase, telemetry, RPC-validation, and bot
-- economy work. Until the owner supplies that manifest, capture the complete live
-- post-mod pool once without mutating it.
CT_BOON_PRICE_AUDIT_MARKER = "boon_price_audit:auto_once_bounded_v0.7.279"
mod._ct_boon_pricing_audit = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_pricing_audit")
mod._ct_boon_pricing_policy = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_pricing_policy")
mod._ct467_audit_done = false
mod._ct467_last_audit = nil

function mod._ct467_flat_text(value, limit)
    local text = tostring(value or "")
    text = text:gsub("[\r\n\t]+", " "):gsub("%s+", " ")
    limit = limit or 240
    if #text > limit then text = text:sub(1, limit - 3) .. "..." end
    return text
end

function mod._ct_boon_price_audit_once(force, run_controller)
    if mod._ct467_audit_done and not force then return mod._ct467_last_audit end
    local by_rarity = rawget(_G, "DeusPowerUpsArrayByRarity")
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local costs = rawget(_G, "DeusCostSettings")
    local price_by_rarity = costs and costs.shop and costs.shop.power_ups
    if type(by_rarity) ~= "table" or type(templates) ~= "table"
        or type(price_by_rarity) ~= "table" then
        return nil
    end

    local max_records = 192
    local report = mod._ct_boon_pricing_audit.audit(
        by_rarity, price_by_rarity, templates, max_records)
    if report.total <= 0 then return nil end
    mod._ct467_audit_done = true
    mod._ct467_last_audit = report

    local profile_index, career_index
    local run_state = run_controller and run_controller._run_state
    if run_state and run_state.get_own_peer_id and run_state.get_player_profile then
        local own_peer = run_state:get_own_peer_id()
        profile_index, career_index = run_state:get_player_profile(own_peer, REAL_PLAYER_LOCAL_ID)
    end

    pcall(printf, "[ct:467] summary total=%d cap=%d stock_prices{event=%s rare=%s exotic=%s unique=%s}",
        report.total, max_records, tostring(price_by_rarity.event), tostring(price_by_rarity.rare),
        tostring(price_by_rarity.exotic), tostring(price_by_rarity.unique))
    for _, rarity in ipairs({ "event", "rare", "exotic", "unique" }) do
        pcall(printf, "[ct:467] tier rarity=%s count=%d shop=%s",
            rarity, report.counts[rarity] or 0, tostring(price_by_rarity[rarity]))
    end

    for _, record in ipairs(report.records) do
        local template = templates[record.name]
        local display = record.display_key or record.name
        if mod._ct_boon_display_name then
            local ok, resolved = pcall(mod._ct_boon_display_name, record.name)
            if ok and resolved then display = resolved end
        elseif record.display_key and rawget(_G, "Localize") then
            local ok, resolved = pcall(Localize, record.display_key)
            if ok and resolved then display = resolved end
        end

        local description = record.description_key or ""
        local entry
        for _, candidate in ipairs(by_rarity[record.rarity] or {}) do
            if type(candidate) == "table" and (candidate.name or candidate[1]) == record.name then
                entry = candidate
                break
            end
        end
        if entry and rawget(_G, "DeusPowerUpUtils")
            and type(DeusPowerUpUtils.get_power_up_description) == "function" then
            local ok, resolved = pcall(DeusPowerUpUtils.get_power_up_description,
                entry, profile_index, career_index)
            if ok and resolved then description = resolved end
        elseif template and template.advanced_description and rawget(_G, "Localize") then
            local ok, resolved = pcall(Localize, template.advanced_description)
            if ok and resolved then description = resolved end
        end
        local exact_price = mod._ct_boon_pricing_policy.price(
            record.name, record.rarity, 0, 100)
        local price_tier = mod._ct_boon_pricing_policy.tier(record.name, record.rarity)
        pcall(printf, "[ct:467] row name=%s rarity=%s shop=%s rework=%s price_tier=%s display=%s description=%s",
            record.name, tostring(record.rarity), tostring(record.shop_price),
            tostring(exact_price), tostring(price_tier),
            mod._ct467_flat_text(display, 120), mod._ct467_flat_text(description, 240))
    end
    for _, anomaly in ipairs(report.anomalies) do
        pcall(printf, "[ct:467] anomaly %s", mod._ct467_flat_text(anomaly, 180))
    end
    pcall(printf, "[ct:467] complete emitted=%d truncated=%d anomalies=%d observation_only=true",
        #report.records, report.truncated, #report.anomalies)
    return report
end

function mod._ct_bot_economy_active()
    return effective_setting("bots_mirror_host_boons")
        or effective_setting("bots_get_random_boons")
        or effective_setting("bots_mirror_host_weapon_upgrades")
end

function mod._ct_bot_economy_log(fmt, ...)
    if mod._ct_bot_economy_log_count >= 64 then return end
    mod._ct_bot_economy_log_count = mod._ct_bot_economy_log_count + 1
    pcall(printf, "[ct:466] " .. fmt, ...)
end

function mod._ct_bot_economy_players()
    local pm = Managers.player
    local players = pm and pm.human_and_bot_players and pm:human_and_bot_players()
    local bots = {}
    for _, player in pairs(players or {}) do
        if player and player.bot_player then bots[#bots + 1] = player end
    end
    return bots
end

function mod._ct_bot_economy_charge(run_state, bot, cost, reason)
    local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
    local ledger_key = tostring(peer_id) .. ":" .. tostring(local_player_id)
    local before
    if mod._ct_bot_economy_initialized[ledger_key] then
        before = run_state:get_player_soft_currency(peer_id, local_player_id) or 0
    else
        local host_peer = run_state:get_server_peer_id()
        before = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID) or 0
        run_state:set_player_soft_currency(peer_id, local_player_id, before)
        mod._ct_bot_economy_initialized[ledger_key] = true
    end
    local affordable, after = mod._ct_bot_economy.charge(before, cost)
    if affordable then run_state:set_player_soft_currency(peer_id, local_player_id, after) end
    mod._ct_bot_economy_log("charge bot=%s reason=%s cost=%s before=%s after=%s allowed=%s",
        tostring(bot.name and bot:name() or local_player_id), tostring(reason), tostring(cost),
        tostring(before), tostring(after), tostring(affordable))
    return affordable
end

function mod._ct_bot_economy_credit_all(run_state, earned)
    for _, bot in ipairs(mod._ct_bot_economy_players()) do
        local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
        local before = run_state:get_player_soft_currency(peer_id, local_player_id) or 0
        local ledger_key = tostring(peer_id) .. ":" .. tostring(local_player_id)
        local after
        if mod._ct_bot_economy_initialized[ledger_key] then
            after = mod._ct_bot_economy.credit(before, earned)
        else
            -- A mode enabled after bot creation has no seed event. At the first
            -- observed host pickup, initialize to the host's already-updated live
            -- balance instead of losing all pre-toggle earnings.
            local host_peer = run_state:get_server_peer_id()
            after = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID) or 0
            mod._ct_bot_economy_initialized[ledger_key] = true
        end
        run_state:set_player_soft_currency(peer_id, local_player_id, after)
        mod._ct_bot_economy_log("credit bot=%s earned=%s before=%s after=%s",
            tostring(bot.name and bot:name() or local_player_id), tostring(earned),
            tostring(before), tostring(after))
    end
end

function mod._ct_bot_economy_seed_all(run_state)
    local host_peer = run_state:get_server_peer_id()
    local host_balance = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID) or 0
    for _, bot in ipairs(mod._ct_bot_economy_players()) do
        local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
        local ledger_key = tostring(peer_id) .. ":" .. tostring(local_player_id)
        run_state:set_player_soft_currency(peer_id, local_player_id, host_balance)
        mod._ct_bot_economy_initialized[ledger_key] = true
        mod._ct_bot_economy_log("seed bot=%s balance=%s at run setup",
            tostring(bot.name and bot:name() or local_player_id), tostring(host_balance))
    end
end

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
        -- #460: once map three begins, reduce the configured multiplier by the
        -- requested percentage. The master toggle gates both advanced options;
        -- the difficulty-increase sub-toggle is intentionally independent.
        local policy = mod._ct_progressive_policy
        if policy and effective_setting("progressive_difficulty") then
            local run_state = self and self._run_state
            local completed = (run_state and run_state.get_completed_level_count
                and run_state:get_completed_level_count()) or 0
            local reduction = effective_setting("progressive_coin_reduction")
            multiplier = policy.coin_multiplier(multiplier, reduction, completed)
            if completed >= 2 and completed ~= self._ct_progcoin_last_logged then
                self._ct_progcoin_last_logged = completed
                pcall(printf, "[ct:460] map=%d completed=%d coin_multiplier=%.3f reduction=%s%%",
                    completed + 1, completed, multiplier, tostring(reduction))
            end
        end
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
    end

    local result_a, result_b = func(self, unpack(args, 1, n))
    if type(args[1]) == "number" and args[1] > 0 and self and self._run_state
        and self._run_state:is_server() and mod._ct_bot_economy_active() then
        mod._ct_bot_economy_credit_all(self._run_state, args[1])
    end
    return result_a, result_b
end)

-- ============================================================
-- Reusable altars -> _ct_altar_reuse_owner.lua (#1159)
-- ============================================================
-- Owns everything ct does that depends on a Chaos Wastes ALTAR
-- (DeusChestExtension: the boon shrine, the two weapon-swap shrines, the
-- weapon-upgrade shrine) having been opened before -- the #61 per-type use
-- ledger and its max-uses / cost-multiplier policies, the mult^uses price
-- curve, the re-roll seed mixing on all three generators, the #102 relaxed
-- lit/interactable gates plus the #252 upgrade-panel repaint that agrees with
-- them, the v0.7.151 collected_by_peers retraction and its ct_altar_uncollect
-- RPC, and the read-only v0.7.157 altar_visual_probe watcher. The terminology
-- banner that governs all of it (an ALTAR is not a Chest of Trials) moved into
-- that file with the code it governs.
--
-- Installed HERE, at the exact position the inline block occupied, so hook
-- registration order and the load-time definition of _ct_altar_probe_watch,
-- _ct_probe_collected_by_peers, the two CT_RELIQUARY_REROLL_* globals, the four
-- mod._ct_* altar helpers, and mod._ct_boon_altar_taken_boons are all unchanged.
--
-- The single WRITE seam -- the consolidated (DeusChestExtension, open_chest)
-- hook that increments the ledger and performs the re-arm -- stays in
-- _ct_bot_weapon_chest_owner; the two exports captured here are forwarded to it
-- at its own install site further down, alongside the two probe globals the
-- module defines. `effective_setting` crosses as a WRAPPER CLOSURE, never by
-- value: its forward slot (declared ~line 785) is still nil at this point and
-- is only assigned in the multiplayer settings-sync block below, so a by-value
-- bind would freeze nil into every altar-reuse setting read.
local _ct_altar_reuse = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner")(mod, {
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    effective_setting = function(setting_id)
        return effective_setting(setting_id)
    end,
    rpc_schema = CT_RPC_SCHEMA,
})

-- ============================================================
-- Host-authoritative settings + graph transport -> _ct_host_state_transport_owner.lua
-- ============================================================
-- The live late-bound slots remain in this entry chunk; the owner calls wrappers so
-- peer-manifest and boon-balance modules can still fill them after transport installs.
local sync_host_dependent_state
local _ct_host_transport = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_host_state_transport_owner")(mod, {
    adventure_pool = AdventurePool,
    broadcast_local_manifest = function(...)
        if _broadcast_local_manifest then return _broadcast_local_manifest(...) end
    end,
    cjson = cjson,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    mod_version = MOD_VERSION,
    rpc_schema = CT_RPC_SCHEMA,
    rt_register = _rt_register,
    sync_host_dependent_state = function(...)
        if sync_host_dependent_state then return sync_host_dependent_state(...) end
    end,
})
local SYNC_CHUNK_SIZE = _ct_host_transport.chunk_size
local SYNCED_SETTING_NAMES = _ct_host_transport.synced_setting_names
local _collect_setting_ids = _ct_host_transport.collect_setting_ids
local _ct_host_settings = _ct_host_transport.host_settings
local apply_graph_snapshot = _ct_host_transport.apply_graph_snapshot
local apply_host_graph_snapshot_to_live_run =
    _ct_host_transport.apply_host_graph_snapshot_to_live_run
local broadcast_graph_snapshot = _ct_host_transport.broadcast_graph_snapshot
local _ct_enqueue_chunk = _ct_host_transport.enqueue_chunk

-- ============================================================
-- Peer manifest diagnostics -> _ct_peer_manifest_owner.lua (#1159)
-- ============================================================
-- Installed at the former inline block position so the manifest RPC and /peers
-- command keep their registration order. The earlier settings-sync receiver
-- calls the returned broadcaster through the existing late-bound entry slot;
-- run creation consumes the returned build/log helpers below.
local _ct_peer_manifest = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_manifest_owner")(mod, {
    chunk_size = SYNC_CHUNK_SIZE,
    cjson = cjson,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    enqueue_chunk = _ct_enqueue_chunk,
    mod_version = MOD_VERSION,
    rpc_schema = CT_RPC_SCHEMA,
    synced_setting_names = SYNCED_SETTING_NAMES,
})
_broadcast_local_manifest = _ct_peer_manifest.broadcast_local_manifest

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
mod._ct_effective_setting_source = function()
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then return "local_host" end
    return _ct_host_transport.host_sync_received() and "host_sync" or "local_fallback"
end

-- #221: one bounded, observation-only summary of the five CT umbrella owners.
-- Uses the realized synced setting inventory, so generated/additional leaves are
-- counted without another hand-maintained list.
mod._ct_umbrella_audit = function(echo_result)
    local totals = { curses = 0, grudges = 0, traits = 0, boons = 0 }
    local active = { curses = 0, grudges = 0, traits = 0, boons = 0 }
    local policy = mod._ct_umbrella_policy
    for _, id in ipairs(SYNCED_SETTING_NAMES) do
        local family
        local master
        if id:find("^disable_curse_") then
            family, master = "curses", "disable_all_listed_curses"
        elseif id:find("^ban_grudge_mark_") then
            family, master = "grudges", "ban_all_grudge_marks"
        elseif id:find("^ban_trait_") and not id:find("_group$") then
            family, master = "traits", "ban_all_traits"
        elseif id:find("^enable_boon_") and id ~= "enable_boon_reworks" then
            family, master = "boons", "enable_boon_reworks"
        end
        if family then
            totals[family] = totals[family] + 1
            local on
            if family == "boons" then
                on = policy.enabled(effective_setting(master), effective_setting(id))
            else
                on = policy.banned(effective_setting(master), effective_setting(id))
            end
            if on then active[family] = active[family] + 1 end
        end
    end
    local line = string.format(
        "[ct:221] altar_master=%s curses_master=%s curses=%d/%d " ..
        "grudges_master=%s grudges=%d/%d traits_master=%s traits=%d/%d " ..
        "boons_master=%s boons=%d/%d mutation=false",
        tostring(effective_setting("enable_altar_reuse") ~= false),
        tostring(effective_setting("disable_all_listed_curses") == true),
        active.curses, totals.curses,
        tostring(effective_setting("ban_all_grudge_marks") == true),
        active.grudges, totals.grudges,
        tostring(effective_setting("ban_all_traits") == true),
        active.traits, totals.traits,
        tostring(effective_setting("enable_boon_reworks") ~= false),
        active.boons, totals.boons)
    pcall(printf, "%s", line)
    if echo_result then mod:echo("[ct:221] umbrella audit written to log") end
    return { totals = totals, active = active, line = line }
end

mod._ct_umbrella_audit(false)

mod:command("ct_umbrella_audit", "Log issue #221 umbrella-master state", function()
    mod._ct_umbrella_audit(true)
end)

-- ============================================================
-- Run lifecycle and backend safety -> _ct_run_runtime_owner.lua
-- ============================================================
local _ct_run_runtime = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_runtime_owner")(mod, {
    altar_reuse = _ct_altar_reuse,
    bomb_boon_names = BOMB_BOON_NAMES,
    capture_returns = _capture_returns,
    chest_default = CHEST_DEFAULT,
    collect_setting_ids = _collect_setting_ids,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    defeat_recovery_triggered = function(value)
        if value ~= nil then _defeat_recovery_triggered_this_round = value end
        return _defeat_recovery_triggered_this_round
    end,
    dump_pickup_spawners_verbose = function(...) return _dump_pickup_spawners_verbose(...) end,
    dump_pickup_system_state = function(...) return _dump_pickup_system_state(...) end,
    effective_setting = effective_setting,
    finale_gods = FINALE_GODS,
    host_sync_received = _ct_host_transport.host_sync_received,
    mod_version = MOD_VERSION,
    peer_manifest = _ct_peer_manifest,
    real_player_local_id = REAL_PLAYER_LOCAL_ID,
    rpc_schema = CT_RPC_SCHEMA,
    rt_register = _rt_register,
    set_career_exclusive_denial_counts = function(value)
        _career_exclusive_denial_counts = value
    end,
    set_career_exclusive_logged_this_run = function(value)
        _career_exclusive_logged_this_run = value
    end,
    shrine_default = SHRINE_DEFAULT,
    starting_coins_applied_for_run = function(value)
        if value ~= nil then _starting_coins_applied_for_run = value end
        return _starting_coins_applied_for_run
    end,
    sync_bomb_cooldown = function() return sync_bomb_cooldown() end,
    sync_boon_movespeed = function() return sync_boon_movespeed() end,
    sync_reckless_swings = function() return sync_reckless_swings() end,
})
is_curse_disabled = _ct_run_runtime.is_curse_disabled
-- ============================================================
-- Adventure runtime and map presentation -> _ct_adventure_runtime_owner.lua
-- ============================================================
local _ct_adventure_runtime = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_adventure_runtime_owner")(mod, {
    adventure_pool = AdventurePool,
    apply_graph_snapshot = apply_graph_snapshot,
    apply_host_graph_snapshot_to_live_run = apply_host_graph_snapshot_to_live_run,
    broadcast_graph_snapshot = broadcast_graph_snapshot,
    dbg = _dbg,
    effective_setting = effective_setting,
    finale_gods = FINALE_GODS,
    host_graph_snapshot = _ct_host_transport.host_graph_snapshot,
    is_curse_disabled = is_curse_disabled,
})
_dump_pickup_system_state = _ct_adventure_runtime.dump_pickup_system_state
_dump_pickup_spawners_verbose = _ct_adventure_runtime.dump_pickup_spawners_verbose
local ADVENTURE_INCOMPATIBLE_PACK_MUTATORS =
    _ct_adventure_runtime.adventure_incompatible_pack_mutators
local on_injected_adventure_level = _ct_adventure_runtime.on_injected_adventure_level
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

-- ============================================================
-- Pickup spawn identity + payout -> _ct_pickup_spawn_owner.lua (#1159)
-- ============================================================
-- Owns every "WHAT unit materializes at this spawn seam, and what does it pay
-- out" decision: the collectible -> Pilgrim's Coin identity rewrite on both
-- seams (PickupSystem._spawn_pickup and the chest-loot-dice
-- UnitSpawner.spawn_network_unit bypass, #134/#351), the #294 non-resident
-- residency guard, the book-pedestal ladder in
-- PickupSystem._spawn_guaranteed_pickup (Chest of Trials -> Belakor locus ->
-- big coin casket -> empty, #60), the big-casket 3x payout on
-- GameModeDeus._get_coins_amount_and_type, and the #58/#143 census probes those
-- seams carry.
--
-- Composes with _ct_spawn_eligibility_owner (installed just below), which owns
-- the orthogonal "MAY this pickup claim this spawner" question
-- (PickupSystem._can_spawn). The two share no hook and no helper.
--
-- dofile'd HERE, at the exact point the block used to execute, so hook
-- registration order, the load-time provenance markers, and the [ct-probe]
-- receipt ordering are unchanged. The module reads the entry's helpers through
-- the mod._ct_* seams published earlier in this chunk, and shares the two
-- per-level counters this file's populate_pickups hook resets as mod fields
-- (mod._ct_chest_conversions_this_level / mod._ct_belakor_altar_spawned_this_level)
-- because the lexical closure binding that made them file-locals cannot reach
-- across chunks.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner")

-- Pickup spawn-eligibility gating -> _ct_spawn_eligibility_owner.lua (#1159).
-- Owns the PickupSystem._can_spawn hook, the career-exclusive blocklist denial,
-- the v0.7.165-dev coin-reservation partition, and the unit-loadability
-- pre-flight. Installed HERE (not earlier) so mod._ct_rebuild_coin_reserved_set
-- is assigned at the same point in the script body as before the extraction --
-- the populate_pickups hook above resolves that field at CALL time.
-- The two per-run telemetry tables are passed as GETTERS, not values: the
-- populate_pickups hook REASSIGNS them to fresh tables at run boot, so a
-- captured reference would freeze this owner on the load-time tables.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_spawn_eligibility_owner").install({
    mod                         = mod,
    dbg                         = _dbg,
    on_injected_adventure_level = on_injected_adventure_level,
    career_exclusive_blocklist  = _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST,
    get_denial_counts           = function() return _career_exclusive_denial_counts end,
    get_logged_this_run         = function() return _career_exclusive_logged_this_run end,
})

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

-- #350 early reward access is presentation-only while vanilla remains RUNNING;
-- register its hooks and runtime policy check before the completion-only OPEN hook.
do
    local cost_feature = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost")
    for _, c in ipairs(cost_feature.rt_checks or {}) do _rt_register(c.name, c.fn) end
    local feature = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_early_reward")
    for _, c in ipairs(feature.rt_checks or {}) do _rt_register(c.name, c.fn) end
end

-- ============================================================
-- Respawn / Revive on Chest of Trials Completion
-- ============================================================
-- The whole feature - completion detection, the three-downed-state triage, the
-- #299 move-before-free rescue transaction, and the post-respawn temporary
-- health / wound compensations - lives in _ct_chest_revive_owner.lua (#1159).
--
-- Installed HERE, at the exact point its DeusCursedChestExtension._set_state
-- hook occupied, so hook-registration order is unchanged: the #350 Chest of
-- Trials interaction hooks dofile'd just above still register BEFORE the
-- completion-only OPEN hook, which is what the comment on that block asks for.
--
-- The owner returns nothing. Its seams stay `mod._ct*` fields because two
-- readers in THIS file cross the chunk boundary and resolve them at call time:
-- mod._ct_chest_teleport_tick (driven by the mod.update tick near the top of
-- this file) and mod._ct_chest_revive_policy / _ct299_arm / _ct299_process /
-- _ct_pending_team_teleport (read by the
-- issue299_chest_revive_team_teleport_ordered regression check below).
--
-- `effective_setting` crosses as a WRAPPER CLOSURE rather than by value. Its
-- body is assigned well above this install site, so a by-value bind would work
-- today; the wrapper makes the binding independent of where this install site
-- sits, matching _ct_altar_reuse_owner (#1236) where an earlier install
-- position made late binding mandatory.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_owner")(mod, {
    effective_setting = function(setting_id)
        return effective_setting(setting_id)
    end,
})

-- ============================================================
-- ============================================================
-- Starting boons, grant sources, and grudge sync -> _ct_boon_runtime_owner.lua
-- ============================================================
local _ct_boon_runtime = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_runtime_owner")(mod, {
    altar_reuse = _ct_altar_reuse,
    capture_returns = _capture_returns,
    career_exclusive_pickups_blocklist = _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST,
    collect_setting_ids = _collect_setting_ids,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    defeat_recovery_triggered = function(value)
        if value ~= nil then _defeat_recovery_triggered_this_round = value end
        return _defeat_recovery_triggered_this_round
    end,
    effective_setting = effective_setting,
    get_career_exclusive_denial_counts = function()
        return _career_exclusive_denial_counts
    end,
    meta_ammo_cap = CT_META_AMMO_CAP,
    meta_ammo_cost_multiplier = _ct_meta_ammo_cost_multiplier,
    meta_ammo_floor = CT_META_AMMO_FLOOR,
    meta_ammo_marker = CT_META_AMMO_HYPERBOLIC_MARKER,
    meta_ammo_max_stacks = CT_META_AMMO_MAX_STACKS,
    meta_ammo_step = CT_META_AMMO_STEP,
    mod_version = MOD_VERSION,
    mutex = _ct_mutex,
    real_player_local_id = REAL_PLAYER_LOCAL_ID,
    rpc_schema = CT_RPC_SCHEMA,
    rt_register = _rt_register,
    starting_coins_mode_marker = STARTING_COINS_MODE_MARKER,
    synced_setting_names = SYNCED_SETTING_NAMES,
})
local sync_grudge_marks = _ct_boon_runtime.sync_grudge_marks
-- ============================================================
-- Boon module install + setting lifecycle -> _ct_settings_lifecycle_owner.lua
-- ============================================================
local _ct_settings_lifecycle = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_settings_lifecycle_owner")(mod, {
    adventure_pool = AdventurePool,
    dbg = _dbg,
    dump_pickup_system_state = _dump_pickup_system_state,
    effective_setting = effective_setting,
    mod_version = MOD_VERSION,
    mutex = _ct_mutex,
    rt_register = _rt_register,
    sync_grudge_marks = sync_grudge_marks,
})
sync_reckless_swings = _ct_settings_lifecycle.sync_reckless_swings; sync_bomb_cooldown = _ct_settings_lifecycle.sync_bomb_cooldown
sync_ulric_pack_unlimited_range = _ct_settings_lifecycle.sync_ulric_pack_unlimited_range; sync_boon_movespeed = _ct_settings_lifecycle.sync_boon_movespeed
sync_host_dependent_state = _ct_settings_lifecycle.sync_host_dependent_state
-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- Most of the suite is extracted VERBATIM to _ct_regression.lua (OOP W5,
-- issue #2) and installed here, at the suite's ORIGINAL position, so append
-- order into _RT_CHECKS (= /ct_regression_test print order) is unchanged: the
-- ~30 scattered checks above register first, this suite next, the trailing
-- feature-module checks last. Each check returns nil for PASS or an error
-- string for FAIL. Registration rides mod._ct_rt_register (same _RT_CHECKS).
-- ============================================================
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_regression")(mod, {
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    mod_version = MOD_VERSION,
    rpc_schema = CT_RPC_SCHEMA,
    meta_ammo_max_stacks = CT_META_AMMO_MAX_STACKS,
    meta_ammo_cost_multiplier = _ct_meta_ammo_cost_multiplier,
    clamp_network_bounded_max = _clamp_network_bounded_max,
    dump_pickup_system_state = _dump_pickup_system_state,
    dump_pickup_spawners_verbose = _dump_pickup_spawners_verbose,
    disabled_dormant_boon_names = CT_DISABLED_DORMANT_BOON_NAMES,
    disabled_dormant_rarities = CT_DISABLED_DORMANT_RARITIES,
    dormant_purge_verified = CT_DORMANT_PURGE_VERIFIED,
    adventure_incompatible_pack_mutators = ADVENTURE_INCOMPATIBLE_PACK_MUTATORS,
    starting_coins_mode_marker = STARTING_COINS_MODE_MARKER,
    variadic_arity_marker = CT_VARIADIC_ARITY_MARKER,
    open_chest_consolidated_marker = CT_OPEN_CHEST_CONSOLIDATED_MARKER,
    meta_ammo_hyperbolic_marker = CT_META_AMMO_HYPERBOLIC_MARKER,
    cot_enemy_mult_marker = CT_COT_ENEMY_MULT_MARKER,
    altar_reuse_hook_marker = CT_ALTAR_REUSE_HOOK_MARKER,
    career_exclusive_pickups_blocklist = _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST,
    mutex = _ct_mutex,
})

-- starting_coins_value_matches_setting stays INLINE (NOT extracted): its body
-- reads the mutable file-local `_starting_coins_applied_for_run` upvalue that the
-- setup_run starting-coins hook updates per run. Moving it into the module would
-- freeze that read at the dofile-time value (nil) — the dropped-upvalue burn
-- class — silently turning the runtime verify into a permanent no-op PASS. Kept
-- verbatim; it registers last within this suite group (the only print-order
-- shift: this one check moves from its former mid-suite slot to the suite tail).
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
    local setting, configured = mod._ct_starting_coins_policy.resolve(
        mod:get("starting_coins"), nil)
    if not configured then return "Starting Coins setting is invalid" end
    local own_peer_id = rc.get_own_peer_id and rc:get_own_peer_id()
    if not own_peer_id then return "could not resolve own_peer_id" end
    local balance = rc.get_player_soft_currency and rc:get_player_soft_currency(own_peer_id)
    if type(balance) ~= "number" then return "could not read balance" end
    if balance ~= setting then
        return string.format("balance=%d != exact setting=%d (rollover/additive regression?)", balance, setting)
    end
end)


-- Mechanic-tweak sliders (Shadow Homing Skulls stun duration, Adventure RNG-trait
-- odds). Own chunk to stay under the 200-local main-chunk cap; reads via the
-- exposed mod._ct_effective_setting; exposes mod._ct_sync_* for the re-apply hubs.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_mechanic_tweaks")

-- #361 Rotten Miasma: compose permanent carrier ownership and host-effective
-- radius/exposure timing onto vanilla's one networked safe-area unit.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_miasma")

-- Consolidated bot features: coin pickup (1s) + Blessed Bots (2s). Host-side;
-- single PlayerBotBase.update hook; no network registration.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_blessed_bots")

-- Duplicate-career map-vote chips: when two peers share a career (gt's
-- allow_duplicate_careers), show BOTH voters' chips on the CW map screen instead
-- of one overwriting the other, distinguished by offset+scale. Client-side render
-- only (no new sync). Hooks DeusMapDecisionView._update_player_state (place extras)
-- + DeusMapScene._clear (teardown extras — no leak). Sole hooks on those pairs.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_dup_vote_chips")

-- #253 Weave-wind curse feasibility: observation-only catalog/resource audit.
-- All eight vanilla templates depend on Managers.weave; do not activate them.
-- Module self-registers through mod._ct_rt_register to preserve the main chunk's
-- hard 200-local ceiling.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_curse_audit")

-- #289 multiple-modifier feasibility: observation-only census of vanilla's
-- singular node curse plus list-valued minor/event/effective/active surfaces.
-- It does not activate or inject a mutator; host/client signatures are the
-- compatibility gate before any bounded ramp is exposed.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_modifier_stack_audit")

-- #323 progressive elite modifiers: observation-only spawn census. The source
-- proves two elite-safe event enhancements but not the 13 boss grudge marks;
-- no enhancement payload is injected until the compatibility gate is complete.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_audit")
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_audit")

-- #919: installed after all owner helpers exist; runtime boundaries above use
-- mod-field forward references and therefore remain safe during file load.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_profile_snapshot").install(mod)

pcall(printf, "[mem-probe] ct boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CT) / 1024)
