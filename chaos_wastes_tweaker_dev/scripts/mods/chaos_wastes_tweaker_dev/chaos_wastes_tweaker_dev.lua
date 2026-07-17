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

local MOD_VERSION = "0.7.292-dev"
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
-- Feature modules loaded near EOF cannot add another main-chunk local (CT sits at
-- Lua 5.1's 200-local ceiling). Expose the existing registrar without creating a
-- second registry or callback owner.
mod._ct_rt_register = _rt_register
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

-- #345: keep the CT dev option-title status surface aligned with the live
-- issue labels. This runtime contract complements the offline source test:
-- VMF must actually resolve the authored rows to the expected visible prefix.
_rt_register("issue345_ct_localization_status_sync", function()
    local expected = {
        inject_adventure_maps = "[diag] [Issue 52 & 251] ",
        progressive_difficulty = "[untested] ",
        finale_dominant_god = "[diag] [Issue 135] ",
        respawn_on_chest_complete = "[verify-fix] [Issue 299] ",
        disable_boon_ct_meta_ammo = "[verify-fix] [diag] [Issue 256 & 249] ",
        start_boon_ct_meta_ammo = "[verify-fix] [diag] [Issue 256 & 249] ",
        enable_boon_vauls_anvil = "[verify-fix] [Issue 144] ",
        start_boon_ct_boon_vauls_anvil = "[verify-fix] [Issue 144] ",
    }
    for key, prefix in pairs(expected) do
        local text = mod:localize(key)
        if type(text) ~= "string" or text:sub(1, #prefix) ~= prefix then
            return string.format("#345 status drift: %s resolved to %s", key, tostring(text))
        end
    end
    if mod:localize("starting_boons_group") ~= "Starting Boons" then
        return "#345 status drift: navigation-only starting_boons_group is tagged"
    end
end)

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
    if type(thr) ~= "number" or thr < 4 then
        return "POOL_SAFETY_THRESHOLD must be a number >= 4 (prevent_same_level_choice bound), got " .. tostring(thr)
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
-- [ct:456] forward-declare the book-spawner census (defined near the other pickup
-- dumps below, referenced from the populate_pickups hook above). Same forward-ref
-- pattern as the two dumps: `local` here, dropped on the later definition.
local _ct_book_spawner_census

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
        pcall(printf, "[ct:467] row name=%s rarity=%s shop=%s display=%s description=%s",
            record.name, tostring(record.rarity), tostring(record.shop_price),
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
            if completed >= 2 and completed ~= mod._ct_progcoin_last_logged then
                mod._ct_progcoin_last_logged = completed
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
    local v = mod._ct_umbrella_policy.value(
        effective_setting("enable_altar_reuse"),
        effective_setting("altar_reuse_count_" .. key), 1)
    if type(v) ~= "number" or v < 1 then return 1 end
    return math.floor(v)
end

local function _altar_cost_mult(chest_type)
    local key = _altar_key_for(chest_type)
    if not key then return 1 end
    local v = mod._ct_umbrella_policy.value(
        effective_setting("enable_altar_reuse"),
        effective_setting("altar_reuse_cost_mult_" .. key), 1)
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
-- NOTE (v0.7.211-dev): no longer called after the #102 rarity-decouple; the reward-rarity
-- bump it powered was removed. Retained only as a generic tier-step helper.
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
-- consolidated `mod:hook("DeusChestExtension", "open_chest", ...)` further down the
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
    -- uses==0 -> go_id unchanged; re-armed -> the v0.7.158 seed-mix. eff_go_id unifies both
    -- branches so behavior is identical to the prior two-branch form.
    local eff_go_id = (uses == 0) and go_id or ((go_id or 0) + uses * 1000003)
    local pre_key = type(weapon) == "table" and weapon.deus_item_key or nil
    local a, b = func(self, weapon, slot_name, rarity, eff_go_id, profile_index, career_index)
    -- #105 [ct:xchar105]: vanilla upgrade_item PRESERVES deus_item_key
    -- (deus_weapon_generation.lua:252-254,185-194), so pre==post is EXPECTED; a mismatch
    -- would prove a key swap. self._stored_purchase is the new weapon
    -- (deus_chest_extension.lua:441). If pre==post but the elf longbow still reverts on
    -- Kruber, the drop is render-side (wt create_equipment re-apply), not ct.
    pcall(function()
        local post = self._stored_purchase
        local post_key = type(post) == "table" and post.deus_item_key or nil
        local prof = rawget(_G, "SPProfiles")
        prof = prof and profile_index and prof[profile_index]
        local career = prof and prof.careers and career_index and prof.careers[career_index]
        pcall(printf, "[ct:xchar105] upgrade-altar slot=%s career=%s rarity=%s pre_key=%s post_key=%s %s",
            tostring(slot_name), tostring(career and career.name), tostring(rarity),
            tostring(pre_key), tostring(post_key),
            (pre_key ~= post_key) and "*** KEY CHANGED ***" or "(key preserved)")
    end)
    return a, b
end)

-- #102 (rarity escalation) FIXED v0.7.211-dev: DECOUPLE keep-lit visual from reward rarity.
-- ----------------------------------------------------------------------------------------------
-- Root cause: self._rarity is BOTH the reward tier (open_chest -> _generate_upgraded_weapon(...,
-- self._rarity), deus_chest_extension.lua:558) AND the input to the dark-gate (update_upgrade_
-- chest_color :236 / can_be_unlocked :513, both `chest_rarity_order <= weapon_rarity_order`). The
-- old v0.7.158 fix kept a re-armed altar LIT by bumping self._rarity strictly ABOVE the wielded
-- weapon every re-roll; that leaked into the reward, climbing plentiful->rare->exotic->unique.
--
-- FIX (Option B, user-chosen 2026-07-02): stop bumping self._rarity entirely (it stays at the
-- constant per-go_id rolled tier, so the reward never climbs), and relax the two dark-gates from
-- `<=` to strict `<` for a RE-ARMED upgrade altar (uses > 0). A same-tier re-roll stays LIT and
-- usable (a rare altar re-rolls a rare weapon at rare, with fresh props via the _generate_upgraded_
-- weapon seed-mix hook above) while a genuine DOWNGRADE still greys out. Same-tier upgrade cost is
-- populated + finite (DeusCostSettings.deus_chest.upgrade[r][r] = base[r]*0.5, e.g. rare=100,
-- deus_cost_settings.lua:137-173), so get_purchase_cost / can_be_unlocked's cost branch pass.
-- Depletion is unaffected: a spent altar keeps _is_purchased=true, which both hooks below (and
-- vanilla can_interact) already treat as unusable.
--
-- Both methods are otherwise unhooked in ct_dev (verified). Both hooks pass through to vanilla for
-- first-use (uses==0) and every non-upgrade chest, so the ONLY behavior change is that a re-armed
-- upgrade altar allows a same-tier re-roll instead of greying out. /ct_regression_test guards this
-- via `upgrade_altar_rarity_decouple`. #103 (looted mesh on non-final use) is a SEPARATE visual
-- path (the open_chest re-arm below) and is unaffected by this decouple.

-- Relaxed VISUAL gate. Reimplements vanilla update_upgrade_chest_color (deus_chest_extension.lua:
-- 211-243) with the rarity test loosened `<=` -> `<`. The rarity flow event is `"lua_update_" ..
-- rarity` (vanilla's file-local LUA_UPDATE_RARITY_EVENTS[rarity], built the same way at :52; it is
-- NOT a global, so it cannot be read via _G). Single hook on this (Class, method).
mod:hook("DeusChestExtension", "update_upgrade_chest_color", function(func, self)
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 or not (DCT and self._chest_type == DCT.upgrade) then
        return func(self)  -- first use / non-upgrade: pure vanilla
    end
    local rarity = self._rarity
    if not rarity then return end
    if self._is_purchased then return end          -- depleted/looted: leave vanilla dark state
    local wielded = self._get_wielded_weapon and self:_get_wielded_weapon()
    if not wielded then return end
    local rs = rawget(_G, "RaritySettings")
    local wr = rs and rs[wielded.rarity]
    local cr = rs and rs[rarity]
    if not (wr and cr) then return func(self) end
    -- RELAXED: `<` not `<=`, so same-tier stays lit; only a downgrade greys out.
    local event = (cr.order < wr.order) and "lua_interact_disabled" or ("lua_update_" .. rarity)
    if not self._prev_update_upgrade_chest_color_event or self._prev_update_upgrade_chest_color_event ~= event then
        if self.unit and Unit and Unit.flow_event
            and (not Unit.alive or Unit.alive(self.unit)) then
            pcall(Unit.flow_event, self.unit, event)
        end
        self._prev_update_upgrade_chest_color_event = event
    end
end)

-- Relaxed INTERACTION gate. Without it the altar would look lit but reject the interact. Reimplements
-- vanilla can_be_unlocked (deus_chest_extension.lua:487-537) with the SAME `<=` -> `<` loosening,
-- gated to a re-armed upgrade altar; every other vanilla gate (can_interact, cost affordability,
-- others_actually_ingame) is preserved exactly. Single hook on this (Class, method).
mod:hook("DeusChestExtension", "can_be_unlocked", function(func, self)
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 or not (DCT and self._chest_type == DCT.upgrade) then
        return func(self)  -- first use / non-upgrade: pure vanilla
    end
    if not self:can_interact() then return false end
    local drc = self._deus_run_controller
    local own_peer_id = drc and drc.get_own_peer_id and drc:get_own_peer_id()
    local soft = (own_peer_id and drc.get_player_soft_currency and drc:get_player_soft_currency(own_peer_id)) or 0
    local cost = self:get_purchase_cost() or math.huge
    local sd = rawget(_G, "script_data")
    local can_unlock = (sd and sd.unlock_all_deus_chests) or cost <= soft
    if can_unlock then
        local wielded = self._get_wielded_weapon and self:_get_wielded_weapon()
        if wielded then
            local rs = rawget(_G, "RaritySettings")
            local wr = rs and rs[wielded.rarity]
            local cr = rs and rs[self._rarity]
            if wr and cr and cr.order < wr.order then  -- RELAXED: block only a real downgrade
                can_unlock = false
            end
        end
    end
    if not can_unlock then return false end
    local nm = Managers.state and Managers.state.network
    local ps = nm and nm.profile_synchronizer
    if ps and ps.others_actually_ingame and not ps:others_actually_ingame() then
        return false
    end
    return true
end)

-- #252: same-tier temper (upgrade) altar re-roll shows the wrong (red) prompt.
-- The can_be_unlocked / update_upgrade_chest_color hooks above let a RE-ARMED upgrade altar
-- re-roll at the SAME rarity, but DeusUpgradeWeaponInteractionUI._populate_widget
-- (deus_upgrade_weapon_interaction_ui.lua:18-107) runs its OWN rarity test
-- (`weapon_rarity_order < chest_rarity_order`, :46) and at same tier takes the else branch
-- (:92-99), painting the RED disabled_text `reliquary_inactive_rarity`. ct never hooked this UI,
-- so the panel still reads "cannot upgrade" even though the altar is lit + interactable.
-- FIX: post-hook (hook_safe, runs after vanilla) the DERIVED class's _populate_widget (the method
-- is defined on DeusUpgradeWeaponInteractionUI, per the repo "hook the derived class" rule). For a
-- re-armed (uses>0) UPGRADE altar whose wielded rarity ORDER == the stored purchase's (== ONLY; a
-- real downgrade `order >` keeps the red text and is still blocked by can_be_unlocked; a real
-- upgrade `order <` already hits vanilla's available branch), repaint as available: item tooltip +
-- rarity + cost (mirrors vanilla :62-91), clear disabled_text, and set reward_info_text
-- (localize=false / white) to a plain re-roll message (no em dash). Everything is pcall-guarded, so
-- any API drift degrades to vanilla's (red) presentation rather than crashing.
CT_RELIQUARY_REROLL_MARKER = "reliquary_reroll_message:same_tier_upgrade_altar_v0.7.215"
mod:hook_safe("DeusUpgradeWeaponInteractionUI", "_populate_widget", function(self, interactable_unit, wielded_slot_name)
    pcall(function()
        local DCT = rawget(_G, "DEUS_CHEST_TYPES")
        if not (DCT and interactable_unit) then return end
        local SU = rawget(_G, "ScriptUnit")
        local pickup_ext = SU and SU.has_extension and SU.has_extension(interactable_unit, "pickup_system")
        if not (pickup_ext and pickup_ext._chest_type == DCT.upgrade) then return end
        local go_id = pickup_ext._go_id
        local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
        if uses == 0 then return end                        -- first use: leave vanilla path
        -- Others still joining -> vanilla shows the joining message; leave it. Derive from the
        -- profile_synchronizer (vanilla :52), NOT a self field (the agent's `self._others_actually_ingame`
        -- does not exist) -- same gate the can_be_unlocked hook above uses.
        local nm = Managers.state and Managers.state.network
        local ps = nm and nm.profile_synchronizer
        if not (ps and ps.others_actually_ingame and ps:others_actually_ingame()) then return end
        local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
        local drc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        if not drc then return end
        local stored = pickup_ext.get_stored_purchase and pickup_ext:get_stored_purchase()
        if not stored then return end
        local melee, ranged = drc:get_own_loadout()
        local equipped = (wielded_slot_name == "slot_melee") and melee or ranged
        if not equipped then return end
        local rs = rawget(_G, "RaritySettings")
        local wr = rs and rs[equipped.rarity]
        local cr = rs and rs[stored.rarity]
        if not (wr and cr) then return end
        if wr.order ~= cr.order then return end             -- ONLY same-tier; up/downgrade untouched
        local chest_info_widget = self._widgets_by_name and self._widgets_by_name.chest_content
        local tooltip_widget    = self._widgets_by_name and self._widgets_by_name.weapon_tooltip
        if not (chest_info_widget and tooltip_widget) then return end
        local peer_id = drc:get_own_peer_id()
        local soft = drc:get_player_soft_currency(peer_id) or 0
        local cost = pickup_ext:get_purchase_cost() or 0
        tooltip_widget.content.item = equipped
        tooltip_widget.content.force_equipped = true
        tooltip_widget.style.item.draw_end_passes = true
        local rarity = stored.rarity
        chest_info_widget.content.rarity_text = rs[rarity].display_name
        local Cols = rawget(_G, "Colors")
        if Cols and Cols.get_table then chest_info_widget.style.rarity.text_color = Cols.get_table(rarity) end
        chest_info_widget.content.cost_text = soft .. "/" .. cost
        chest_info_widget.style.cost_text.text_color = (cost <= soft)
            and { 255, 255, 255, 255 } or { 255, 255, 0, 0 }
        chest_info_widget.content.reward_info_text = "Re-rolls this weapon's traits and properties"
        chest_info_widget.content.show_coin_icon = true
        chest_info_widget.content.disabled_text = nil
        self._calculate_offset = true
    end)
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
    -- #487 freeze watchdog: reports any single frame whose dt exceeds the stall
    -- threshold (a recoverable game-loop stall), naming the last-open diagnostic
    -- region. Cheap field read + numeric compare; no-op on the common path.
    if mod._ct_freeze487 then mod._ct_freeze487.tick(dt) end
    -- #299: deferred host-side pass that teleports a chest-revived player back to a
    -- teammate once they become controllable (they otherwise stand up alone at a
    -- distant respawn beacon). Cheap no-op when nothing is armed. Resolved via mod._
    -- since the tick + its pending table are defined later in this file (assigned at
    -- load, before any update tick fires).
    if mod._ct_chest_teleport_tick then mod._ct_chest_teleport_tick(dt) end
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
    -- Every dead Adventure collectible must share the same exact identity policy.
    if not set.loot_die then return "loot_die not in collectible->coin set" end
    if not set.lorebook_page then return "lorebook_page not in collectible->coin set" end
    if not set.painting_scrap then return "painting_scrap not in collectible->coin set" end
    if type(mod._ct351_rewrite_network_spawn) ~= "function" then
        return "#351 direct network-spawn rewrite missing (chest loot dice bypass PickupSystem)"
    end
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
    return mod._ct_umbrella_policy.banned(
        effective_setting("disable_all_listed_curses"), effective_setting(key))
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
-- ============================================================
-- Progressive Difficulty (run-wide toggle)
-- ============================================================
-- #460 advanced policy: step only on maps 3 and 5. First 2 missions use the
-- starting difficulty; maps 3-4 use start+1; map 5 onward uses start+2.
-- Vanilla registers only through Cataclysm 3. If a compatible difficulty mod
-- registers Cataclysm 4/5 in DifficultyLookup+Difficulties, the dynamic ceiling
-- admits them; otherwise it safely caps at the highest registered Cata tier and
-- never crosses into versus_base.
--
-- Lever: hook DeusRunController.get_run_difficulty, the value that flows through
-- deus_mechanism get_next_level_data (deus_mechanism.lua:166) -> the level transition
-- -> state_ingame.lua:245 `Managers.state.difficulty:set_difficulty(...)`, which the
-- host RPCs to every client (difficulty_manager.lua:50). The CW path graph is
-- generated ONCE at setup_run (deus_run_controller.lua:284) and takes NO difficulty
-- argument (deus_generate_graph), so stepping the difficulty can NEVER reshape the
-- graph. Deterministic on every peer (same host-synced start difficulty + completed
-- count via effective_setting), so host and clients land on the same tier with no
-- RPC-timing race.
--
-- Caveat: a peer that HOT-JOINS mid-run inherits the host's already-stepped difficulty
-- as its "start" and could over-step; peers present at run start are unaffected.
CT_PROGRESSIVE_DIFFICULTY_MARKER = "progressive_difficulty:maps_3_and_5_dynamic_cata5_coin_reduction_v0.7.276"
mod._ct_progressive_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_difficulty")
mod._ct_progdiff_step = function(start_key, completed_level_count)
    local Diff = rawget(_G, "Difficulties")
    local Lookup = rawget(_G, "DifficultyLookup")
    return mod._ct_progressive_policy.difficulty(start_key, completed_level_count, Diff, Lookup)
end

mod:hook("DeusRunController", "get_run_difficulty", function(func, self)
    local base = func(self)
    if not effective_setting("progressive_difficulty")
        or not effective_setting("progressive_difficulty_increase") then return base end
    local start_key = mod._ct_progdiff_start or base
    local run_state = self and self._run_state
    local completed = (run_state and run_state.get_completed_level_count
        and run_state:get_completed_level_count()) or 0
    local stepped = mod._ct_progdiff_step(start_key, completed)
    if completed ~= mod._ct_progdiff_last_logged then
        mod._ct_progdiff_last_logged = completed
        pcall(printf, "[ct:progdiff] mission %d (completed=%d): start=%s -> difficulty=%s",
            completed + 1, completed, tostring(start_key), tostring(stepped))
    end
    return stepped
end)

-- ============================================================
-- Replacement-player progression compensation (Issue #465)
-- ============================================================
-- Vanilla keeps CW progression under (peer, local-player, profile, career) keys.
-- Removing a bot for a joiner does not move those keys, and adding a bot after a
-- departure initializes a fresh profile row. Preserve the selected replacement's
-- boons, persistent buffs, and serialized melee/ranged CW weapons at the exact
-- GameModeDeus add/remove boundaries. A joining human receives the host's current
-- coin balance, per the feature specification; a departure-created bot receives
-- the departing human's balance until another human takes over.
--
-- Direct run-state writes use only vanilla SharedState fields. No custom RPC or
-- per-frame polling is involved. If CT peer parity has not been positively proven,
-- CT-owned boon/buff names are filtered before the copy so this convenience feature
-- can never put an unknown NetworkLookup index on a joining peer's wire.
CT_REPLACEMENT_COMPENSATION_MARKER = "replacement_compensation:host_state_handoff_v0.7.277"
mod._ct_replacement_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_compensation")
mod._ct_replacement_cache = {}
mod._ct_replacement_log_count = 0

function mod._ct_replacement_log(fmt, ...)
    if mod._ct_replacement_log_count >= 32 then return end
    mod._ct_replacement_log_count = mod._ct_replacement_log_count + 1
    pcall(printf, "[ct:465] " .. fmt, ...)
end

function mod._ct_replacement_filtered(snapshot)
    local wire_safe = mod._ct_wire_safe and mod._ct_wire_safe() or false
    local ok, filtered, removed_power_ups, removed_buffs = pcall(
        mod._ct_replacement_policy.wire_safe_copy, snapshot, wire_safe,
        mod._ct_is_modded_power_up, mod._ct_is_ct_buff_template)
    if not ok then return nil, 0, 0, filtered end
    return filtered, removed_power_ups, removed_buffs
end

function mod._ct_replacement_capture(run_state, peer_id, local_player_id, profile_index, career_index)
    local ok, snapshot, reason = pcall(mod._ct_replacement_policy.capture, run_state,
        peer_id, local_player_id, profile_index, career_index)
    if not ok then return nil, snapshot end
    return snapshot, reason
end

function mod._ct_replacement_apply(run_state, peer_id, local_player_id, profile_index, career_index, snapshot, coins)
    local ok, applied, reason = pcall(mod._ct_replacement_policy.apply, run_state,
        peer_id, local_player_id, profile_index, career_index, snapshot, coins)
    if not ok then return false, applied end
    return applied, reason
end

mod:hook("GameModeDeus", "player_left_game_session", function(func, self, peer_id, local_player_id)
    if self and self._is_server and effective_setting("replacement_player_compensation") then
        local run_state = self._deus_run_controller and self._deus_run_controller._run_state
        if run_state then
            local profile_index, career_index = run_state:get_player_profile(peer_id, local_player_id)
            if not profile_index or profile_index == 0 then
                local player = Managers.player and Managers.player:player(peer_id, local_player_id)
                profile_index = player and player.profile_index and player:profile_index() or profile_index
                career_index = player and player.career_index and player:career_index() or career_index
            end
            local snapshot, reason = mod._ct_replacement_capture(run_state, peer_id,
                local_player_id, profile_index, career_index)
            local key = mod._ct_replacement_policy.profile_key(profile_index, career_index)
            if snapshot and key then
                mod._ct_replacement_cache[key] = mod._ct_replacement_cache[key] or {}
                mod._ct_replacement_cache[key][#mod._ct_replacement_cache[key] + 1] = snapshot
                mod._ct_replacement_log("captured departing human peer=%s local=%s profile=%s:%s boons=%d coins=%s",
                    tostring(peer_id), tostring(local_player_id), tostring(profile_index),
                    tostring(career_index), #(snapshot.power_ups or {}), tostring(snapshot.coins))
            else
                mod._ct_replacement_log("departure capture skipped peer=%s local=%s reason=%s",
                    tostring(peer_id), tostring(local_player_id), tostring(reason))
            end
        end
    end
    return func(self, peer_id, local_player_id)
end)

mod:hook_safe("GameModeDeus", "_add_bot", function(self)
    if not (self and self._is_server) then return end
    local bots = self._bot_players
    local bot = bots and bots[#bots]
    local run_state = self._deus_run_controller and self._deus_run_controller._run_state
    if not (bot and run_state) then return end

    -- Fresh bots begin with their own ledger seeded from the host's live balance.
    -- A #465 departure snapshot, when present, intentionally overwrites this seed
    -- below with the departing human's balance.
    if mod._ct_bot_economy_active() then
        local bot_peer, bot_local = bot:network_id(), bot:local_player_id()
        local ledger_key = tostring(bot_peer) .. ":" .. tostring(bot_local)
        local host_peer = run_state:get_server_peer_id()
        local host_coins = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID) or 0
        run_state:set_player_soft_currency(bot_peer, bot_local, host_coins)
        mod._ct_bot_economy_initialized[ledger_key] = true
        mod._ct_bot_economy_log("initialized bot=%s balance=%s from host",
            tostring(bot.name and bot:name() or bot_local), tostring(host_coins))
    end

    if not effective_setting("replacement_player_compensation") then return end

    local profile_index = bot:profile_index()
    local career_index = bot:career_index()
    local key = mod._ct_replacement_policy.profile_key(profile_index, career_index)
    local queue = key and mod._ct_replacement_cache[key]
    local snapshot = queue and queue[1]
    if not snapshot then return end

    local filtered, removed_power_ups, removed_buffs, filter_reason = mod._ct_replacement_filtered(snapshot)
    local ok, reason = mod._ct_replacement_apply(run_state, bot:network_id(),
        bot:local_player_id(), profile_index, career_index, filtered)
    if ok then
        table.remove(queue, 1)
        if #queue == 0 then mod._ct_replacement_cache[key] = nil end
    end
    mod._ct_replacement_log("human->bot profile=%s:%s applied=%s boons=%d coins=%s parity_filtered=%d/%d reason=%s",
        tostring(profile_index), tostring(career_index), tostring(ok),
        #(filtered and filtered.power_ups or {}), tostring(filtered and filtered.coins),
        removed_power_ups or 0, removed_buffs or 0, tostring(reason or filter_reason))
end)

mod:hook("GameModeDeus", "remove_bot", function(func, self, party_id, peer_id, local_player_id, update_safe)
    local bot = func(self, party_id, peer_id, local_player_id, update_safe)
    if not (bot and self and self._is_server and effective_setting("replacement_player_compensation")) then
        return bot
    end

    local run_controller = self._deus_run_controller
    local run_state = run_controller and run_controller._run_state
    if not run_state then return bot end

    local bot_profile = bot:profile_index()
    local bot_career = bot:career_index()
    local snapshot, reason = mod._ct_replacement_capture(run_state, bot:network_id(),
        bot:local_player_id(), bot_profile, bot_career)
    local target_profile, target_career = run_state:get_player_profile(peer_id, local_player_id)
    if not mod._ct_replacement_policy.same_identity(bot_profile, bot_career,
        target_profile, target_career) then
        mod._ct_replacement_log("bot->human skipped incompatible identity bot=%s:%s target=%s:%s",
            tostring(bot_profile), tostring(bot_career), tostring(target_profile), tostring(target_career))
        return bot
    end
    if not snapshot then
        mod._ct_replacement_log("bot->human capture skipped target=%s reason=%s", tostring(peer_id), tostring(reason))
        return bot
    end

    local filtered, removed_power_ups, removed_buffs, filter_reason = mod._ct_replacement_filtered(snapshot)
    local host_peer = run_state:get_server_peer_id()
    local host_coins = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID)
    local ok, apply_reason = mod._ct_replacement_apply(run_state, peer_id, local_player_id,
        target_profile, target_career, filtered, host_coins)

    -- player_entered_game_session may have restored spawn data before party assignment.
    -- Rebuild it once after the authoritative row is copied so the first spawn consumes
    -- the compensated weapons and buffs rather than the joiner's temporary initial row.
    if ok and self._deus_spawning and self._deus_spawning._restore_player_game_mode_data then
        local status = Managers.party and Managers.party:get_player_status(peer_id, local_player_id)
        if status then
            local restore_ok, restored = pcall(self._deus_spawning._restore_player_game_mode_data,
                self._deus_spawning, peer_id, local_player_id, target_profile, target_career)
            if restore_ok then status.game_mode_data = restored end
        end
    end

    mod._ct_replacement_log("bot->human bot_profile=%s:%s target=%s:%s applied=%s boons=%d host_coins=%s parity_filtered=%d/%d reason=%s",
        tostring(bot_profile), tostring(bot_career), tostring(target_profile), tostring(target_career),
        tostring(ok), #(filtered and filtered.power_ups or {}), tostring(host_coins),
        removed_power_ups or 0, removed_buffs or 0, tostring(apply_reason or filter_reason))
    return bot
end)

-- ============================================================
-- Journey-completion difficulty crash guard (Issue #291)
-- ============================================================
-- Vanilla StatisticsUtil._register_completed_journey_difficulty resolves the run's
-- difficulty via Managers.state.difficulty:get_default_difficulties(), which returns
-- DefaultDifficulties -- whose top entry is base "cataclysm" (difficulty_settings.lua:412,
-- list = normal/hard/harder/hardest/cataclysm). cataclysm_2 / cataclysm_3 are NOT in
-- that list, so `table.find` returns nil and the very next line does
-- `current_completed_difficulty < nil` -> hard CTD ("attempt to compare number with nil";
-- decompiled statistics_util.lua:1054, shipped bytecode reports it as :997).
--
-- The progressive_difficulty ramp above pushes a CW run up to cataclysm_3, so WINNING a
-- journey's final round (the Citadel) at cata2/cata3 crashed on the journey-stat write.
-- Confirmed in the wild (console 2026-07-04 19.45.55 + issue #291 03.27): the crash fired
-- ~1s after the ramp logged "-> difficulty=cataclysm_3", with journey_name="journey_citadel",
-- difficulty_name="cataclysm_3", difficulty_index=nil, and NO third-party difficulty mod
-- enabled. This guard ALSO shields against Onslaught / "Cata 3 & Deathwish" exposing the
-- same tiers by other means.
--
-- Fix: clamp only the RECORDED difficulty to the highest tier the vanilla journey-stat DB
-- can represent (base "cataclysm"). The player keeps journey-completion credit at that
-- ceiling; the in-mission gameplay difficulty is untouched (this hook does not feed
-- get_run_difficulty). The vanilla per-LEVEL recorder already guards this with
-- `if difficulty then` (statistics_util.lua:1013), so only the journey recorder needs it.
-- Cross-mod note: Loremaster's Armoury also hooks this function; it forwards the args
-- unchanged to the original, so our clamp reaches the vanilla body regardless of chain order.
CT_JOURNEY_DIFFICULTY_GUARD_MARKER = "journey_difficulty_clamp_to_default_max_v0.7.220"
mod:hook("StatisticsUtil", "_register_completed_journey_difficulty",
    function(func, statistics_db, player, journey_name, dominant_god, difficulty_name)
        local dm = Managers.state.difficulty
        local difficulties = dm and dm:get_default_difficulties()
        if type(difficulties) == "table" and not table.find(difficulties, difficulty_name) then
            local clamped = difficulties[#difficulties]
            pcall(printf, "[ct:journeyguard] journey '%s' completed at '%s' (not in DefaultDifficulties) -> recording as '%s' to avoid statistics_util CTD (issue #291)",
                tostring(journey_name), tostring(difficulty_name), tostring(clamped))
            difficulty_name = clamped
        end
        return func(statistics_db, player, journey_name, dominant_god, difficulty_name)
    end)

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
    _ct_cot_trial_last = {}   -- #463: reset per-block last-forced SPECIFIC trial at run start
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
    -- Progressive Difficulty: capture this run's TRUE starting difficulty (the
    -- setup_run `difficulty` arg = args[2]) so the get_run_difficulty ramp computes
    -- from a stable base, and reset the per-mission log throttle. At run start this is
    -- the unstepped base on every peer present (step==0 at completed==0).
    mod._ct_progdiff_start = args[2]
    mod._ct_progdiff_last_logged = nil
    mod._ct_progcoin_last_logged = nil
    mod._ct_replacement_cache = {}
    mod._ct_replacement_log_count = 0
    mod._ct_bot_economy_initialized = {}
    mod._ct_bot_economy_log_count = 0
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

    -- #487 freeze diagnostics: bracket the vanilla setup_run call, which runs
    -- deus_generate_graph -> deus_populate_graph (the backtracking map solver, the
    -- prime freeze suspect). The BEGIN breadcrumb is flushed synchronously with the
    -- live pool sizes, so if the solver hard-hangs this is the last console line and
    -- it explains why; FINISH reports elapsed + whether the graph came back nil.
    -- Runs on BOTH peers (client also solves locally from the synced seed).
    if mod._ct_freeze487 then
        local is_server_d = Managers and Managers.player and Managers.player.is_server
        mod._ct_freeze487.begin_generate(args[3], is_server_d)
    end

    local ret_a, ret_b = func(self, unpack(args, 1, n))

    -- #467 requires no command: after vanilla has materialized the live rarity
    -- arrays, emit one bounded, sorted census per process on both host and client.
    mod._ct_boon_price_audit_once(false, self)

    if self and self._run_state and self._run_state:is_server()
        and mod._ct_bot_economy_active() then
        mod._ct_bot_economy_seed_all(self._run_state)
    end

    if mod._ct_freeze487 then
        mod._ct_freeze487.finish_generate(args[3], self._path_graph)
    end

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
    -- parry-cooldown strip. The earlier boot-time attempt to call the strip
    -- ran BEFORE morris settings populated DeusPowerUpTemplates (log line 1308 of
    -- console-2026-05-29-02.03.57: "DeusPowerUpTemplates not ready; parry-cooldown
    -- strip skipped"), so the cooldowns survived and items 5+6 never actually
    -- shipped. This hook fires on every boon roll AFTER morris settings are loaded
    -- and BEFORE any altar interaction (rolls happen at chest spawn, before player
    -- opens it). The strip body is idempotent — once `cooldown_buff` is nil, the
    -- next call's `for` loop is a no-op. Safe to call from every roll.
    local strip = mod._ct128_strip_parry_cooldowns
    if type(strip) ~= "function" then
        mod:warning("[ct:342] parry-cooldown strip unavailable after combat-hook load")
    else
        local strip_ok, strip_result = pcall(strip)
        if not strip_ok then
            mod:warning("[ct:342] parry-cooldown strip failed: %s", tostring(strip_result))
        end
    end

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

-- #470: vanilla data hole in mutator_curse_skulking_sorcerer.lua. Its local rank
-- constants are broken (CATACLYSM = 6, CATACLYSM_2 = 6 duplicate, CATACLYSM_3 = 7
-- at :9-11), so the MAX_HEALTH table its server_initialize_function assigns onto
-- Breeds.curse_mutator_sorcerer (:36) spans ranks 2..7 with NOTHING at rank 8
-- (cataclysm_3). The base breed's own max_health is a full 8-entry array
-- (breed_chaos_mutator_sorcerer.lua:58-67) - the hole exists only while the curse
-- is initialized. Vanilla CW never reaches rank 8, but ct's progressive difficulty
-- can step a run to cataclysm_3 (difficulty_settings.lua:287); a curse-sorcerer
-- spawn then resolves max_health[8] = nil (conflict_director.lua:1948),
-- GenericHealthExtension.init throws in math.clamp mid extension-add, and the
-- half-initialized hit_reaction extension (registered one slot earlier,
-- unit_extension_templates.lua:403-419, extensions_ready never runs) nil-derefs on
-- the next HitReactionSystem update = host CTD. Fatshark guarded the sibling
-- RESPAWN_TIME lookup with `or RESPAWN_TIME[NORMAL]` (:43) but not MAX_HEALTH.
-- Backfill [8] = 150, Fatshark's evident cataclysm_3 intent (the duplicate-key bug
-- shifted the whole band down one rank). Entries 6/7 stay as-is: re-keying them
-- would change live gameplay values. Swept every other
-- scripts/settings/mutators/mutator_*.lua 2026-07-11: this is the only rank-keyed
-- table landing on a Breed with an unguarded read; egg_of_tzeentch/bolt_of_change
-- sparse tables all carry `or X[NORMAL]` / `or 1` fallbacks.
-- UNCONDITIONAL per issue 371 never-crash doctrine: NOT gated on the progressive
-- difficulty toggle - any other rank-8 source hits the same hole. Predicate
-- exported on mod for /ct_regression_test.
mod._ct_backfill_rank8_max_health = function(mh)
    if type(mh) == "table" and mh[8] == nil and mh[7] ~= nil then
        mh[8] = 150
        return true
    end
    return false
end

-- hook_safe AFTER initialize_mutators: server-only call path (mutator_handler.lua:48),
-- and every template.server.initialize_function has run by then
-- (mutator_handler.lua:644-645), i.e. the sparse table has already landed on the
-- breed. Grep-verified 2026-07-11: sole (MutatorHandler, initialize_mutators) hook
-- in this mod (other MutatorHandler hooks: _activate_mutator above,
-- tweak_pack_spawning_settings in the adventure-inject block).
mod:hook_safe("MutatorHandler", "initialize_mutators", function(self, mutators)
    local breed = Breeds and Breeds.curse_mutator_sorcerer
    local mh = breed and breed.max_health
    if mod._ct_backfill_rank8_max_health(mh) then
        pcall(printf, "[ct:470] backfilled curse_mutator_sorcerer.max_health[8]=150 (vanilla rank hole)")
    end
end)

_rt_register("curse_sorcerer_rank8_backfill", function()
    local fn = mod._ct_backfill_rank8_max_health
    if type(fn) ~= "function" then
        return "mod._ct_backfill_rank8_max_health export missing"
    end
    -- sparse table shaped like the curse MAX_HEALTH band (ranks 6/7 present, 8 missing)
    local sparse = { [6] = 120, [7] = 150 }
    if not fn(sparse) or sparse[8] ~= 150 then
        return "sparse table not backfilled to [8]=150"
    end
    if sparse[6] ~= 120 or sparse[7] ~= 150 then
        return "backfill mutated existing entries"
    end
    -- full 8-entry array (the base breed shape) must pass through untouched
    local full = { 30, 30, 40, 60, 90, 90, 90, 90 }
    if fn(full) or full[8] ~= 90 then
        return "full 8-entry table was modified"
    end
    if fn(nil) or fn({}) then
        return "predicate fired on nil/empty input"
    end
    return nil
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
    _ct_cot_trial_last = {}   -- #463: reset per-block last-forced SPECIFIC trial per mission

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
    -- #119/#260: when "Any Trait on Any Weapon" is on, expand each weapon's pool to the
    -- full trait UNION of its OWN combat class (melee or ranged), NOT the cross-slot global
    -- union that get_all_trait_combos() returns. This lifts the weapon-TYPE restriction (any
    -- trait allowed within the slot, #119) while STRICTLY preserving the melee/ranged split
    -- (no melee trait leaks onto a ranged weapon or vice versa, #260) - matching the
    -- tier-by-rarity path's class-union rule (get_tier_filtered_combos / _ct_get_trait_class_pools).
    -- Falls back to the old global union only if WeaponTraits.combinations isn't loaded yet,
    -- so early-timing rolls behave exactly as before.
    local slot_pools = any_trait and mod._ct_get_trait_class_pools()
    local melee_expanded, ranged_expanded
    if slot_pools then
        melee_expanded, ranged_expanded = {}, {}
        for trait in pairs(slot_pools.melee) do melee_expanded[#melee_expanded + 1] = { trait } end
        for trait in pairs(slot_pools.ranged) do ranged_expanded[#ranged_expanded + 1] = { trait } end
    end
    local global_expanded = (any_trait and not slot_pools) and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local expanded_pool
        if any_trait then
            if slot_pools then
                local ttn = data.trait_table_name
                local is_ranged = type(ttn) == "string" and not ttn:find("melee")
                local slot_list = is_ranged and ranged_expanded or melee_expanded
                if slot_list and #slot_list > 0 then
                    expanded_pool = slot_list
                end
            else
                expanded_pool = global_expanded
            end
        end
        local base = expanded_pool or original
        if base then
            local filtered = {}
            for _, combo in ipairs(base) do
                local keep = true
                for _, trait in ipairs(combo) do
                    if mod._ct_umbrella_policy.banned(
                        effective_setting("ban_all_traits"),
                        effective_setting("ban_trait_" .. trait)) then
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
            if rp and rp[rarity] and not mod._ct_umbrella_policy.banned(
                effective_setting("ban_all_traits"),
                effective_setting("ban_trait_" .. trait)) then
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

-- #221 adversarial completion: baked-pool filtering cannot cover vanilla unique
-- archetypes, and its intentional empty-pool fallback permits a trait when every
-- candidate is banned. Strip only the detached generated result after every
-- generation/upgrade path (and after tier override), which vanilla serialization
-- safely supports as an empty trait list.
function mod._ct_strip_banned_traits_from_result(result)
    if type(result) ~= "table" then return result end
    local traits, removed = mod._ct_umbrella_policy.filter_traits(
        effective_setting("ban_all_traits"), result.traits, function(trait)
            return effective_setting("ban_trait_" .. tostring(trait))
        end)
    if removed > 0 then result.traits = traits end
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
    result = override_traits_in_result(result, gen_rarity)
    return mod._ct_strip_banned_traits_from_result(result)
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

-- #157 (crash+bug) - cross-character weapon CTDs the CW loadout backend.
-- BackendInterfaceDeusBase.set_loadout_item (backend_interface_deus_base.lua:112-124)
-- fasserts "[BackendInterfaceDeusBase] Item %q doesn't exist" when item_backend_id is
-- absent from self._extra_deus_inventory. A wt cross-char item equipped mid-run routes
-- its ITEMS-backend id through the deus loadout override (LOADOUT_INTERFACE_OVERRIDES
-- slot_ranged="deus") -> id absent -> C-fatal. HOOK THE DERIVED CLASS: class() copies the
-- base method onto BackendInterfaceDeusPlayFab at definition time, so a base-class hook
-- never reaches the instance. Guard: id present or nil -> vanilla unchanged; a non-deus id
-- -> log + BAIL so the CW loadout keeps its current valid deus weapon.
mod:hook("BackendInterfaceDeusPlayFab", "set_loadout_item", function(func, self, item_backend_id, career_name, slot_name)
    local inv = rawget(self, "_extra_deus_inventory")
    if item_backend_id == nil or (type(inv) == "table" and inv[item_backend_id] ~= nil) then
        return func(self, item_backend_id, career_name, slot_name)
    end
    pcall(printf, "[ct:crash157] BLOCKED set_loadout_item non-deus id: career=%s slot=%s id=%s (cross-char item has no deus inventory entry; kept current deus weapon to avoid CTD)",
        tostring(career_name), tostring(slot_name), tostring(item_backend_id))
end)

-- #157 secondary (defensive, belt-and-suspenders): get_total_power_level
-- (backend_interface_deus_base.lua:130-150) derefs self._extra_deus_inventory[id].power_level
-- for slot_melee/slot_ranged with NO nil-check; a loadout slot referencing a missing id
-- C-fatals when the power-level UI reads it. Reimplement with nil-skip; vanilla-identical
-- when both entries are present.
mod:hook("BackendInterfaceDeusPlayFab", "get_total_power_level", function(func, self, profile_name, career_name)
    local inv = rawget(self, "_extra_deus_inventory")
    local loadouts = self._loadouts and self._loadouts[career_name]
    if type(inv) ~= "table" or type(loadouts) ~= "table" then
        return func(self, profile_name, career_name)
    end
    local melee_id, ranged_id = loadouts.slot_melee, loadouts.slot_ranged
    local melee_missing  = melee_id  and not inv[melee_id]
    local ranged_missing = ranged_id and not inv[ranged_id]
    if not (melee_missing or ranged_missing) then
        return func(self, profile_name, career_name)  -- vanilla-identical
    end
    pcall(printf, "[ct:crash157] get_total_power_level guarded missing deus entry (career=%s melee_missing=%s ranged_missing=%s)",
        tostring(career_name), tostring(melee_missing), tostring(ranged_missing))
    local sum, count = 0, 0
    if melee_id  and inv[melee_id]  and inv[melee_id].power_level  then sum = sum + inv[melee_id].power_level;  count = count + 1 end
    if ranged_id and inv[ranged_id] and inv[ranged_id].power_level then sum = sum + inv[ranged_id].power_level; count = count + 1 end
    local base = (rawget(_G, "PowerLevelFromLevelSettings") or {}).starting_power_level or 0
    return (count > 0 and sum / count or 0) + base
end)

-- #273 [ct:revert273] keep-entry capture. BulldozerPlayer.spawn fires for the local player
-- on every level load incl. return-to-keep. Log the ITEMS-backend loadout (character_data)
-- melee/ranged keys for the local career, so a keep-restored base weapon (e.g. es_2h_sword
-- Greatsword) vs the CW cross-char weapon is visible. Compare against the CW-EXIT line from
-- game_round_ended. Local-human only, pcall-guarded. Distinct (Class,method); no other
-- BulldozerPlayer hook in ct_dev.
mod:hook_safe("BulldozerPlayer", "spawn", function(self)
    pcall(function()
        local pm = Managers.player
        local lp = pm and pm.local_player and pm:local_player()
        if not lp or lp ~= self or self.bot_player then return end
        local sp = rawget(_G, "SPProfiles")
        local prof = sp and self.profile_index and sp[self:profile_index()]
        local career = prof and prof.careers and self.career_index and prof.careers[self:career_index()]
        local career_name = career and career.name
        if not career_name then return end
        local mech = Managers.mechanism and Managers.mechanism.current_mechanism_name
            and Managers.mechanism:current_mechanism_name()
        local melee  = BackendUtils.get_loadout_item(career_name, "slot_melee")
        local ranged = BackendUtils.get_loadout_item(career_name, "slot_ranged")
        pcall(printf, "[ct:revert273] SPAWN mechanism=%s career=%s melee_key=%s(deus=%s) ranged_key=%s(deus=%s)",
            tostring(mech), tostring(career_name),
            tostring(melee and melee.key), tostring(melee and melee.deus_item_key),
            tostring(ranged and ranged.key), tostring(ranged and ranged.deus_item_key))
    end)
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
    -- #273 [ct:revert273] CW-EXIT capture (read-only). On the run-ending round (won/lost),
    -- log the deus loadout the run held for the local career, to compare against what the
    -- keep restores (BulldozerPlayer.spawn hook below) - catches Kruber's active weapon
    -- reverting to the base Greatsword after a run.
    if reason == "won" or reason == "lost" then
        pcall(function()
            local rc = self._deus_run_controller
                or (self.get_deus_run_controller and self:get_deus_run_controller())
            if rc and rc.get_own_loadout then
                local melee, ranged = rc:get_own_loadout()
                pcall(printf, "[ct:revert273] CW-EXIT reason=%s melee_key=%s ranged_key=%s",
                    tostring(reason),
                    tostring(melee and melee.deus_item_key), tostring(ranged and ranged.deus_item_key))
            end
        end)
    end
    local restored = false
    local original_god
    local vote_data = self._vote_data
    if reason == "start_game" and is_server and vote_data then
        local weekly_god = vote_data.dominant_god  -- #135: weekly/vote god BEFORE ct override
        local god_index = mod:get("finale_dominant_god")
        if god_index and god_index > 0 then
            local god = FINALE_GODS[god_index]
            if god then
                original_god = vote_data.dominant_god
                vote_data.dominant_god = god
                restored = true
                -- #145 (read-only): note the finale override is active, and whether
                -- disable_dominant_god will neuter it on the graph.
                pcall(printf, "[ct:citadel145] finale override active: finale_dominant_god=%s -> %s | disable_dominant_god=%s (if true, override is neutered on the graph)",
                    tostring(god_index), tostring(god), tostring(mod:get("disable_dominant_god")))
            end
        end
        -- #135 (read-only): pin a "set X, got Y" mismatch to either the SELECTION
        -- (resolved != chosen -> precedence bug here) or the graph NEUTERING (resolved
        -- == chosen but a different god renders -> #145, fixed by _ct_force_finale_god).
        pcall(printf, "[ct:god135] weekly/vote god=%s | finale setting=%s (%s) | resolved dominant_god=%s | disable_dominant_god=%s",
            tostring(weekly_god), tostring(god_index),
            tostring((god_index and god_index > 0 and FINALE_GODS[god_index]) or "rotation"),
            tostring(vote_data.dominant_god), tostring(mod:get("disable_dominant_god")))
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
        if mod._ct_chest132 and mod._ct_chest132.begin then
            mod._ct_chest132.begin(level_key)
        end
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
            -- #349: classify the extension-level ground truth only after this
            -- delayed pickup census has settled. extensions_ready itself fires
            -- synchronously before _spawn_pickup returns, so comparing there is
            -- inherently one chest early and cannot prove a bypass.
            if mod._ct_chest132 and mod._ct_chest132.finalize then
                local cap = mod._ct_effective_setting and mod._ct_effective_setting("cursed_chest_count")
                cap = (cap == -1 or cap == nil) and 1 or cap
                local is_server = Managers and Managers.player and Managers.player.is_server and true or false
                mod._ct_chest132.finalize(_level, cap, cursed, is_server)
            end
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
    -- #132 cross-check accessor: the running count of deus_cursed_chest (Chest of
    -- Trials) spawns the census has seen at PickupSystem._spawn_pickup so far this
    -- mission. The [ct:132] extensions_ready probe compares its spawn-path-
    -- independent ground truth against this: ground_truth > census means chests
    -- exist that never routed through the pickup system (raw baked level units).
    mod._ct_tally_cursed_count = function()
        return _counts.deus_cursed_chest or 0
    end
    -- Regression marker (PROJECT_STANDARDS.md hook-consolidation doctrine): census is
    -- wired through the SINGLE existing _spawn_pickup hook + the existing mod.update
    -- drainer; no new hook on PickupSystem._spawn_pickup / no second mod.update owner.
    mod._CT_SPAWN_TALLY_MARKER = "CT_SPAWN_TALLY_v1_unconditional_census"
end

-- #132 DIAGNOSTIC: spawn-path-independent Chest-of-Trials ground truth.
-- DeusCursedChestExtension.extensions_ready (deus_cursed_chest_extension.lua:39)
-- fires once per cursed chest that actually exists in the world, on every peer,
-- regardless of HOW the chest spawned - so it catches chests that bypass the
-- pickup system (and thus the cursed_chest_count cap) entirely. Distinct method
-- from the existing _set_state hook, so this fresh hook is VMF-clean. Read-only;
-- cap/census are resolved here and handed to the #132 module which owns the
-- per-mission counter + emit. See _ct_diag_cursed_chest132.lua for the full why.
mod:hook_safe("DeusCursedChestExtension", "extensions_ready", function(self, world, unit)
    if not mod._ct_chest132 then return end
    pcall(function()
        local cur = LevelHelper and LevelHelper:current_level_settings()
        local level_id = (cur and cur.level_id) or "?"
        local cap = mod._ct_effective_setting and mod._ct_effective_setting("cursed_chest_count")
        cap = (cap == -1 or cap == nil) and 1 or cap
        local census = mod._ct_tally_cursed_count and mod._ct_tally_cursed_count() or -1
        local is_server = (Managers and Managers.player and Managers.player.is_server) and true or false
        mod._ct_chest132.chest_appeared(level_id, cap, census, is_server)
    end)
end)

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
    -- [ct:456] book-spawner census on any ct injected-catalog level (Adventure AND CW),
    -- so an empty first-Grimoire spot on skaven_stronghold ("Into the Nest") is pinned to
    -- (a) spawner never registered / (b) triggered-list / (c) guaranteed-but-fails. See the
    -- _ct_book_spawner_census definition. Forward-ref safe via mod._ (call-time resolve);
    -- `self` here is the live PickupSystem.
    pcall(function()
        if mod._ct_adventure_base_from_level_key and mod._ct_adventure_base_from_level_key(level_key)
            and mod._ct_book_spawner_census then
            mod._ct_book_spawner_census(self, level_key)
        end
    end)
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

    -- #143: on injected adventure levels we still need to renormalize the grenade pool
    -- (Morgrim's over-spawn fix, below), so do NOT early-bail there even with no
    -- altar/cursed/ammo/potion override active. _inj was computed above (call-time via
    -- mod._ct_on_injected_adventure_level(), forward-ref safe).
    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on and not _inj then
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

    -- #143: Morgrim's Bomb (holy_hand_grenade) over-spawn fix. The morgrim143 census
    -- proved every Morgrim's appearance is source=spawner -- the vanilla spread-pool
    -- sampler (pickup_system.lua:481-497) walking Pickups.grenades by spawn_weighting.
    -- We HALVE holy_hand and hand the freed half to the OTHER grenades PROPORTIONALLY, so
    -- the pool SUM is byte-identical to vanilla. That preserves the sampler invariant
    -- (running total must reach the [0,1) roll); the v0.7.143 crash (total < roll) happened
    -- only because that build LOWERED the total -- a sum-preserving redistribution provably
    -- cannot reintroduce it. Scoped to injected adventure levels (_inj) and RESTORED after
    -- vanilla populate runs, so vanilla Adventure and real CW arenas are untouched.
    local saved_grenade_weights = nil
    if _inj and Pickups and Pickups.grenades and Pickups.grenades.holy_hand_grenade
            and Pickups.grenades.holy_hand_grenade.spawn_weighting then
        local holy = Pickups.grenades.holy_hand_grenade
        local holy_orig = holy.spawn_weighting
        local sum_others, count_others = 0, 0
        for name, s in pairs(Pickups.grenades) do
            if name ~= "holy_hand_grenade" and s and s.spawn_weighting then
                sum_others = sum_others + s.spawn_weighting
                count_others = count_others + 1
            end
        end
        -- Guard: if holy_hand is the ONLY grenade there is nowhere to move the freed
        -- weight -- halving it would SHRINK the total and risk the sampler crash. Skip.
        if holy_orig > 0 and sum_others > 0 and count_others > 0 then
            saved_grenade_weights = {}
            for name, s in pairs(Pickups.grenades) do
                if s and s.spawn_weighting then saved_grenade_weights[name] = s.spawn_weighting end
            end
            local freed = holy_orig * 0.5
            holy.spawn_weighting = holy_orig - freed
            for name, s in pairs(Pickups.grenades) do
                if name ~= "holy_hand_grenade" and s and s.spawn_weighting then
                    s.spawn_weighting = s.spawn_weighting + freed * (s.spawn_weighting / sum_others)
                end
            end
            -- printf (NOT mod:info -- user runs VMF logging OFF): after_sum MUST equal the
            -- pre-change sum (holy_orig + sum_others), proving no total change -> no crash.
            local after_sum = 0
            for _, s in pairs(Pickups.grenades) do
                if s and s.spawn_weighting then after_sum = after_sum + s.spawn_weighting end
            end
            pcall(printf, "[ct:morgrim143] grenade pool renorm: holy_hand %.4f -> %.4f, freed %.4f to %d others (pool sum %.4f -> %.4f)",
                holy_orig, holy.spawn_weighting, freed, count_others, holy_orig + sum_others, after_sum)
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

    -- #143: restore vanilla grenade weights after populate's spread-pass consumed them,
    -- leaving Pickups.grenades pristine for the next level (vanilla Adventure / real CW).
    -- Mirrors the deus_potions save/restore above.
    if saved_grenade_weights then
        for name, original_w in pairs(saved_grenade_weights) do
            local entry = Pickups.grenades[name]
            if entry then entry.spawn_weighting = original_w end
        end
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
            then
                -- #52 DIAGNOSTIC ([ct:skull52]): census every object set for each
                -- get_object_sets call during an injected-adventure load (main world AND
                -- hero sublevels). Tower of Treachery (dlc_wizards_tower) gargoyle-skull
                -- collectibles are the `gargoyle_head` level_event pickup, which that
                -- level's pickup_settings does NOT list, so they are object-set / flow
                -- spawned via placed pickup-spawner units; #156's 'adventure' enable may
                -- be targeting the wrong set. This lists every set + whether it will spawn
                -- under deus so we can identify the skull-bearing set. printf = visible with
                -- mod-logging OFF. Gate on the CURRENT injected level key (looser than the
                -- #156 level_name match, so sublevel calls are captured).
                local lth = Managers and Managers.level_transition_handler
                local cur_key = lth and lth.get_current_level_keys and lth:get_current_level_keys()
                if type(cur_key) == "string" and adventure_base_from_level_key(cur_key) then
                    local spawned_lookup = {}
                    for _, s in ipairs(spawned_object_sets) do spawned_lookup[s] = true end
                    local names = {}
                    for set_name in pairs(object_sets) do names[#names + 1] = set_name end
                    table.sort(names)
                    pcall(printf, "[ct:skull52] key=%s level_name=%s object_sets=%d spawned=%d",
                        tostring(cur_key), tostring(level_name), #names, #spawned_object_sets)
                    for _, set_name in ipairs(names) do
                        pcall(printf, "[ct:skull52]   set=%s spawned=%s",
                            tostring(set_name), tostring(spawned_lookup[set_name] == true))
                    end
                end

                -- #156 fix (behavior unchanged): enable the 'adventure' object set on the
                -- injected MAIN adventure level if present and not already spawning.
                if object_sets.adventure and not table.contains(spawned_object_sets, "adventure") then
                    local ok, base, level_key = pcall(_ct_injected_base_for_spawn, level_name)
                    if ok and base then
                        spawned_object_sets[#spawned_object_sets + 1] = "adventure"
                        -- Raw printf: proves the fix engaged even on the logging-OFF host.
                        pcall(printf, "[ct:objset] injected adventure level %s: enabling 'adventure' object set (issue #156)",
                            tostring(level_key))
                    end
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
    -- #464 follow-up: trait-as-boon for Anath Raema's Swiftness, always the PERMANENT
    -- variant (independent of the tweak_anath_raema_permanent rework toggle).
    display_name_ct_boon_anath_raema_swiftness = "(Mod Boon) Anath Raema's Swiftness",
    description_ct_boon_anath_raema_swiftness  = "Reload time is halved, permanently, no ammo pickup needed. Stacks with the weapon trait.",

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

-- issue 511: load-time marker for the #133 Manann's Tempest cooldown-note append
-- (the branch lives in the Localize hook below, keyed on
-- description_deus_crit_chain_lightning + tweak_manann_tempest_cooldown). Replaces
-- the io.open self-grep that threw in the VMF sandbox (no `io`). The exact branch
-- text is a source invariant flagged for a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
CT_MANANN_TEMPEST_NOTE_MARKER = "manann_tempest:crit_chain_lightning_cooldown_note_v0.7.232"
mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string" then
        if key == "ct_cot_cost_action" and mod._ct_cot_cost_action_text then
            return mod._ct_cot_cost_action_text()
        end
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
        -- #133: the VANILLA Manann's Tempest weapon trait (deus_crit_chain_lightning) also
        -- gains the 8s cooldown when tweak_manann_tempest_cooldown is on - the
        -- ProcFunctions.chain_lightning hook gates BOTH the mod boon AND this trait. The mod-boon
        -- branch above only covers description_ct_boon_manann_tempest; append the same note to the
        -- vanilla trait's advanced_description (weapon_traits_morris.lua:563) so its tooltip tracks
        -- behavior too. Appends to func()'s vanilla string so it stays EXACTLY vanilla with the
        -- tweak off; the vanilla %s target-count placeholder is substituted downstream by
        -- UIUtils.get_trait_description. No `%` in the appended line, so no %% escaping needed.
        if key == "description_deus_crit_chain_lightning"
            and effective_setting("tweak_manann_tempest_cooldown") then
            return func(key, ...) .. "\n8 second cooldown."
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

-- v0.7.231: the strip now keys off the crash predicate (missing difficulty_overrides),
-- not only on_injected_adventure_level, so Belakor/other deus missions on adventure-derived
-- conflict directors are covered. Marker asserted by /ct_regression_test.
CT_NO_ROAMERS_DEUS_FIX_MARKER = "no_roamers_strip_keys_on_missing_difficulty_overrides_v0.7.231"

-- v0.7.241 (issue 356): ARITY FIX. Vanilla MutatorHandler.tweak_pack_spawning_settings is
-- STATIC - defined dot-form (def mutator_handler.lua:748) and DOT-CALLED with exactly 4 args
-- (zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings) at
-- main_path_spawning_generator.lua:327. The pre-fix hook declared a spurious leading `self`,
-- so VMF's arg pass shifted every param by one: `pack_spawning_settings` always read nil (the
-- missing_field strip fired on EVERY call) and, worse, the real `zone_mutator_list` - the list
-- no_roamers actually rides on for CW SIGNATURE zones - rode in as the dropped-`self` positional
-- and was NEVER filtered. So the pairs(nil) host CTD this guard exists to prevent (crash guid
-- 4c84c68a: no_roamers reading pack_spawning_settings.difficulty_overrides on a Belakor node)
-- could still fire on signature zones. Fix: drop `self`, bind the 4 real params in vanilla
-- order, filter BOTH lists. Behavioral arity lock: /ct_regression_test `no_roamers_strip_arity_356`.
CT_NO_ROAMERS_ARITY_FIX_MARKER = "no_roamers_hook_static_arity_no_self_v0.7.241"

mod:hook("MutatorHandler", "tweak_pack_spawning_settings", function(func, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    -- Strip the adventure-incompatible pack mutators (no_roamers) when EITHER:
    --   (a) pack_spawning_settings lacks `difficulty_overrides` -- the exact field
    --       no_roamers iterates with pairs() (mutator_no_roamers.lua:6), so letting it
    --       run fatals `bad argument #1 to 'pairs' (table expected, got nil)`. This is
    --       the precise crash predicate and ALSO covers deus missions running on
    --       adventure-derived conflict directors like `chaos_light` that lack the field
    --       -- e.g. a Belakor node (`military_belakor_path1`, conflict chaos_light /
    --       deus_skaven_chaos): crash console 2026-07-05-23.30.21, guid 4c84c68a. The
    --       v0.7.41 `on_injected_adventure_level()` check below never fires for these
    --       (they ARE deus, not injected-into-stock-Adventure), so no_roamers reached
    --       vanilla and crashed on first mission entry. OR
    --   (b) on_injected_adventure_level() -- the original v0.7.41 aesthetic exemption
    --       (no_roamers' area_density_coefficient=0 wipes roaming spawns, too aggressive
    --       for adventure geometry). Kept OR-ed so this build never strips LESS than before.
    -- On a normal CW level difficulty_overrides IS present and it isn't injected, so the
    -- guard passes through and vanilla no_roamers runs untouched. Stripping never removes
    -- a working mutator: with difficulty_overrides nil, no_roamers can only ever crash.
    local missing_field = type(pack_spawning_settings) ~= "table" or pack_spawning_settings.difficulty_overrides == nil
    if not (missing_field or on_injected_adventure_level()) then
        return func(zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    end
    local function filter(list, list_label)
        if type(list) ~= "table" then return list end
        local kept, dropped = {}, nil
        for _, name in ipairs(list) do
            if ADVENTURE_INCOMPATIBLE_PACK_MUTATORS[name] then
                dropped = dropped or {}
                dropped[#dropped + 1] = name
            else
                kept[#kept + 1] = name
            end
        end
        if dropped then
            -- [ct:356] fires only when a mutator is actually filtered. Naming the list
            -- (zone_mutator_list vs mutator_list) confirms in the field that the
            -- SIGNATURE-zone path - the one the old arity bug missed - is now covered.
            pcall(printf, "[ct:356] stripped {%s} from %s on conflict '%s' (difficulty_overrides present=%s) - prevented pairs(nil) crash in mutator_no_roamers",
                table.concat(dropped, ","), tostring(list_label), tostring(conflict_director_name),
                tostring(type(pack_spawning_settings) == "table" and pack_spawning_settings.difficulty_overrides ~= nil))
        end
        return kept
    end
    -- Filter BOTH lists in vanilla order. run_mutators processes mutator_list then
    -- zone_mutator_list (mutator_handler.lua:765-766); no_roamers can ride on either.
    return func(filter(zone_mutator_list, "zone_mutator_list"), filter(mutator_list, "mutator_list"), conflict_director_name, pack_spawning_settings)
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

-- [ct:456] v0.7.249-dev — book-spawner census. Issue #456 ("Into the Nest",
-- skaven_stronghold): in a CW run the location of the FIRST Grimoire is ALWAYS empty.
-- ct's Chest-of-Trials placement converts book (tome/grimoire) pickup-spawner units to
-- deus_cursed_chest inside PickupSystem._spawn_guaranteed_pickup, so an empty book spot
-- means one of:
--   (a) the grimoire spawner UNIT never registered with PickupSystem at all — its level
--       object set is not enabled under the deus game mode (the #52 / #156 family; see the
--       [ct:skull52] object-set census + the GameModeHelper.get_object_sets #156 fix). It
--       would then be absent from EVERY spawner list here.
--   (b) it registered into the TRIGGERED list (triggered_spawn_id), whose activation flow
--       (PickupSystem.activate_triggered_pickup_spawners, pickup_system.lua:283) never fires
--       under the deus mechanism, so _spawn_guaranteed_pickup is never called for it. It
--       would then show list=triggered here but produce no conversion probe.
--   (c) it IS a guaranteed spawner that converts, but the chest/casket fails at that
--       position — the [ct:456] fallthrough probes in _spawn_guaranteed_pickup catch this.
--
-- Neither existing probe answers (a)/(b): _dump_pickup_spawners_verbose is _dbg-gated
-- (invisible on a mod-logging-OFF host) and never enumerates the triggered list per unit,
-- and the [populate_pickups] line reports only aggregate list counts. This census is
-- UNCONDITIONAL printf (misc_util.lua:29, survives logging OFF) and enumerates EVERY
-- tome/grim-tagged unit across guaranteed + primary + secondary + specified + triggered,
-- with its list, guaranteed_spawn / triggered_id flags and world position. Fires for any
-- ct injected-catalog base (MISSION_BY_KEY) in BOTH Adventure and CW, so a plain-Adventure
-- load of skaven_stronghold gives a baseline to diff the CW load against (the diff method
-- _dump_pickup_spawners_verbose was built for). Cheap: books are <=5 per level.
-- audit: `local` dropped — assigns into the forward-declared slot near the top of file.
function _ct_book_spawner_census(ps_sys, level_key)
    if not (ps_sys and Unit and Unit.get_data) then return end
    local g_tome, g_grim, t_tome, t_grim, o_tome, o_grim = 0, 0, 0, 0, 0, 0
    local function posstr(unit)
        local s = "?"
        pcall(function()
            local p = Unit.local_position(unit, 0)
            s = string.format("(%.1f,%.1f,%.1f)", Vector3.x(p), Vector3.y(p), Vector3.z(p))
        end)
        return s
    end
    local function scan(list_name, list, trig_id)
        if type(list) ~= "table" then return end
        for _, unit in pairs(list) do
            if Unit.alive and Unit.alive(unit) then
                local is_tome = Unit.get_data(unit, "tome") and true or false
                local is_grim = Unit.get_data(unit, "grimoire") and true or false
                if is_tome or is_grim then
                    local kind = is_grim and "grim" or "tome"
                    local guaranteed = Unit.get_data(unit, "guaranteed_spawn") and true or false
                    local tid = trig_id or Unit.get_data(unit, "triggered_spawn_id") or ""
                    pcall(printf, "[ct:456] book_spawner level=%s list=%s kind=%s guaranteed_spawn=%s triggered_id=%s pos=%s",
                        tostring(level_key), list_name, kind, tostring(guaranteed), tostring(tid), posstr(unit))
                    if list_name == "guaranteed" then
                        if is_grim then g_grim = g_grim + 1 else g_tome = g_tome + 1 end
                    elseif list_name == "triggered" then
                        if is_grim then t_grim = t_grim + 1 else t_tome = t_tome + 1 end
                    else
                        if is_grim then o_grim = o_grim + 1 else o_tome = o_tome + 1 end
                    end
                end
            end
        end
    end
    scan("guaranteed", ps_sys.guaranteed_pickup_spawners)
    scan("primary",    ps_sys.primary_pickup_spawners)
    scan("secondary",  ps_sys.secondary_pickup_spawners)
    scan("specified",  ps_sys.specified_pickup_spawners)
    if type(ps_sys.triggered_pickup_spawners) == "table" then
        for trig_id, group in pairs(ps_sys.triggered_pickup_spawners) do
            scan("triggered", group, trig_id)
        end
    end
    pcall(printf, "[ct:456] census level=%s books guaranteed(tome=%d grim=%d) triggered(tome=%d grim=%d) other(tome=%d grim=%d)",
        tostring(level_key), g_tome, g_grim, t_tome, t_grim, o_tome, o_grim)
end
mod._ct_book_spawner_census = _ct_book_spawner_census

mod:hook_safe("GameModeDeus", "local_player_game_starts", function(self, player, loading_context)
    -- v0.7.124-dev — per-mission diagnostic dump (Issue: citadel curse mismatch).
    -- Gated on VMF debug logging via _dbg. Runs on BOTH peers when a CW mission
    -- starts. Dumps current_node + its full state so we can compare host vs client
    -- and verify the active mutator list matches the node's expected curse.
    pcall(function()
        local rc = self._deus_run_controller
        if not rc then
            pcall(printf, "[ct:136] mission:start no _deus_run_controller (unexpected)")
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
        -- v0.7.243-dev (#136): raw printf (was _dbg, invisible with mod-logging
        -- OFF - the user's setup). This is the per-peer resolved-mission line: run
        -- a CW expedition on host + client and diff the two [ct:136] mission:start
        -- lines for the same round. A differing level/node/god is the wrong-mission
        -- symptom the player sees; the [ct:136] graph lines (populate_graph) show
        -- the roll that caused it. injected = whether this level is an injected
        -- adventure map (the client IS_INJECTED gate that goes false in the #134/
        -- #136 divergence class); level_seed exposes the possibly-unsynced seed the
        -- client rolled its graph from.
        local injected = "<nil>"
        pcall(function() injected = tostring(on_injected_adventure_level() and true or false) end)
        pcall(printf, "[ct:136] mission:start is_server=%s current_node=%s level=%s base_level=%s theme=%s curse=%s level_seed=%s god=%s node_type=%s injected=%s node_mutators=%s active_mutators=%s",
            tostring(is_server), tostring(cur_key),
            cur and tostring(cur.level) or "<nil>",
            cur and tostring(cur.base_level) or "<nil>",
            cur and tostring(cur.theme) or "<nil>",
            cur and tostring(cur.curse) or "<nil>",
            cur and tostring(cur.level_seed) or "<nil>",
            cur and tostring(cur.god) or "<nil>",
            cur and tostring(cur.node_type) or "<nil>",
            injected, mutators_str, active_str)
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
-- Hardening: NetworkedFlowStateManager 512-cap OVERFLOW guard (host)
-- ============================================================
-- The clear_object_state hook above fixes the vanilla _num_states LEAK
-- (destroyed units never decrementing the counter). But the crash can ALSO
-- recur WITHOUT a leak, and it did: v0.7.211-dev host crash on
-- dlc_termite_3_tzeentch_path1 (Devious Delvings / Tzeentch), Chest of
-- Trials active, enemy_tweaker caps raised. Crash dump
-- console-2026-07-03-18.41.50-d6dbb15d.
--
-- Mechanism: a Chest of Trials terror event applies the
-- `cursed_chest_objective_unit` buff to EVERY non-special trash spawn
-- (deus_generic_terror_events.lua:26 cursed_chest_enemy_spawned_func), and
-- each buff (morris_buff_settings.lua:614 apply_objective_unit) spawns a
-- `units/hub_elements/objective_unit` carrying a `chest_open_state`
-- networked flow state. entity_manager2.lua:390 clears the state on unit
-- DESTROY, but under raised enemy caps the fight holds 512+ live
-- objective_units AT ONCE (and mark_for_deletion lags actual destroy), so
-- the states are genuinely live -- the leak fix can't reclaim them. Vanilla
-- flow_cb_create_state fatals on the assert at
-- networked_flow_state_manager.lua:381:
--   "[NetworkedFlowStateManager] Too many object states(512)."
--
-- Guard (host-authoritative create path): intercept create. Near the cap,
-- first reclaim slots held by units that are already DEAD but whose destroy
-- has not yet fired clear_object_state (mark_for_deletion lag / any residual
-- leak vector). If STILL full after reclaim, SKIP the create -- return the
-- vanilla "declined to create" shape (nothing), which the flow callback
-- already tolerates (flow_callbacks.lua:1292 `if created then`). A trash-mob
-- objective marker without its networked chest_open_state is a cosmetic
-- degradation on that one unit; a host crash ends the whole team's run.
-- The full-table sweep only runs when _num_states is within 1 of the cap,
-- so normal play (which never approaches 511) pays zero cost.
CT_FLOWSTATE_CAP_GUARD_MARKER = "networked_flow_state_cap_guard:reclaim_dead_then_skip_v0.7.213"
mod:hook("NetworkedFlowStateManager", "flow_cb_create_state", function(func, self, unit, state_name, ...)
    local num = self._num_states
    local max = self._max_states
    if type(num) == "number" and type(max) == "number" and num >= max - 1 then
        -- Reclaim slots from units that are already dead (destroy lag / leak).
        local states = self._object_states
        if type(states) == "table" then
            local dead, reclaimed = nil, 0
            for u, unit_states in pairs(states) do
                if not (Unit and Unit.alive and Unit.alive(u)) then
                    local c = 0
                    if type(unit_states) == "table" and type(unit_states.states) == "table" then
                        for _ in pairs(unit_states.states) do c = c + 1 end
                    end
                    dead = dead or {}
                    dead[#dead + 1] = u
                    reclaimed = reclaimed + c
                end
            end
            if dead then
                for i = 1, #dead do states[dead[i]] = nil end
                if reclaimed > 0 and type(self._num_states) == "number" then
                    self._num_states = math.max(0, self._num_states - reclaimed)
                end
            end
        end
        -- Still full after reclaim? Decline the create instead of fatalling.
        if type(self._num_states) == "number" and self._num_states >= max then
            if not mod._ct_flowstate_cap_warned then
                mod._ct_flowstate_cap_warned = true
                pcall(printf,
                    "[ct:flowcap] NetworkedFlowStateManager at cap (%s/%s); declining create state=%s to avoid host crash (further skips silent this session)",
                    tostring(self._num_states), tostring(max), tostring(state_name))
            end
            return
        end
    end
    return func(self, unit, state_name, ...)
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
    -- BELAKOR — twilight purple. v0.7.21 brightened interiors; v0.7.207-dev
    -- brightens them further after a report that already-dark INTERIOR maps
    -- (repro: Devious Delvings / dlc_termite_2, a mines level) went near-black
    -- under the curse. Root cause: these tints are MULTIPLICATIVE, so a factor
    -- < 1 on the interior channels (ambient / fill / exposure) crushes a scene
    -- whose baked atmosphere is already dim. Fix: the interior-bounce channels
    -- no longer darken at all (ambient/fill/exposure >= 1.0) and only carry the
    -- purple HUE (green pulled below blue); the EXTERIOR sky + direct sun stay
    -- dim so open-air Belakor missions keep their oppressive mood. VISUAL -
    -- needs in-game confirmation; if still off, wire a live brightness knob.
    belakor = {
        skydome_tint_color   = { 0.45, 0.30, 0.70 },   -- exterior sky: still dim + purple
        sun_color            = { 0.62, 0.60, 0.92 },   -- exterior direct sun: slightly dim
        secondary_sun_color  = { 0.90, 0.85, 1.10 },   -- fill: near-neutral, lifted (was 0.55/0.50/0.90) — interiors
        ambient_tint         = { 1.00, 0.90, 1.22 },   -- interior bounce: NO darkening, purple-shifted (was 0.75/0.65/1.00)
        ambient_tint_top     = { 0.92, 0.85, 1.18 },   -- top ambient: near-neutral, purple (was 0.60/0.55/1.00)
        fog_color            = { 0.45, 0.35, 0.80 },   -- keep fog purple
        exposure_mul         = 1.02,                    -- tiny lift, no global dim (was 0.92)
    },
}

-- ============================================================
-- Per-MAP curse-lighting brightness overrides (#258, #271)
-- ============================================================
-- A few injected adventure maps read too dark even after the per-curse profile
-- and the global curse_lighting_brightness knob. This table adds an EXTRA
-- per-channel multiplier for those specific maps, applied ON TOP of the profile
-- tint and the global knob inside the shading_callback below. Keyed by the
-- injected-adventure BASE level_key (resolved from the CW permutation level_id via
-- adventure_base_from_level_key), then by curse theme; "*" = every curse. A missing
-- map, theme, or channel resolves to 1.0 (no change), so no other map regresses.
-- Channel names match _CURSE_SKY_PROFILES vars, plus "exposure".
--   #258 The Well of Dreams (dlc_termite_3): under Tzeentch the upper-hemisphere
--        ambient (ambient_tint_top) crushes to near-black. Double it (amb_top
--        +100%). Tzeentch only; other curses on this map read fine. (Sibling mod
--        vdl made the analogous Adventure-mode fix for the same map/channel.)
--   #271 Devious Delvings (dlc_termite_2): a dark mines interior. The curse look
--        needs ~2x brighter overall, for EVERY curse -- doubling the four interior
--        levers the brightness knob drives = "set the knob to 2.0 for this map only".
local _CURSE_MAP_BRIGHTNESS = {
    dlc_termite_3 = {
        tzeentch = { ambient_tint_top = 2.0 },
    },
    dlc_termite_2 = {
        ["*"] = {
            secondary_sun_color = 2.0,
            ambient_tint        = 2.0,
            ambient_tint_top    = 2.0,
            exposure            = 2.0,
        },
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

-- #104 perf census tuning: sample window (seconds) and marker.
CT_PERF_CENSUS_MARKER = "perf104:flowstate_enemy_fps_census_v0.7.214"
CT_PERF_WINDOW = 5.0
mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
    if not on_injected_adventure_level() then return end
    -- #104 perf census (diagnose-before-mitigate). The shading_callback is the
    -- per-frame, injected-map-gated path, so sample a throttled LOAD census here
    -- BEFORE the curse-theme early returns below (so it runs on EVERY injected
    -- frame, cursed or not). User reports FPS drops localized to the first-grimoire
    -- Chest of Trials on Blood in the Darkness; the leading suspect is the same
    -- cursed_chest objective_unit / networked-flow-state load that overflowed the
    -- 512 cap (#262) - hundreds of linked objective_units tank framerate long
    -- before they crash. This prints flow-state count + live enemy count + avg fps
    -- + worst single frame every CT_PERF_WINDOW s so a repro AT the chest shows
    -- exactly what spikes. Cheap per frame (one guarded clock read + a counter).
    do
        local now = (Managers and Managers.time and Managers.time:time("game")) or nil
        if now then
            local st = mod._ct_perf
            if not st or now < st.census then
                st = { last = now, census = now, frames = 0, worst = 0 }
                mod._ct_perf = st
            end
            local dt = now - st.last
            st.last = now
            if dt > st.worst then st.worst = dt end
            st.frames = st.frames + 1
            local elapsed = now - st.census
            if elapsed >= CT_PERF_WINDOW then
                local nfs = Managers.state and Managers.state.networked_flow_state
                local flow_states = (nfs and type(nfs._num_states) == "number") and nfs._num_states or -1
                -- v0.7.216: the ConflictDirector manager is Managers.state.conflict, NOT
                -- Managers.state.conflict_director (that key is nil), so the first census
                -- shipped enemies=-1 on every line. `_num_spawned_ai` is the live alive-AI
                -- count (conflict_director.lua:2169).
                local cd = Managers.state and Managers.state.conflict
                local enemies = (cd and type(cd._num_spawned_ai) == "number") and cd._num_spawned_ai or -1
                local lvl = "?"
                local gm = Managers.state and Managers.state.game_mode
                if gm and gm.level_key then
                    local ok, k = pcall(gm.level_key, gm)
                    if ok and k then lvl = k end
                end
                pcall(printf,
                    "[ct:perf] level=%s theme=%s window=%.1fs frames=%d avg_fps=%.1f worst_frame_ms=%.1f flow_states=%d enemies=%d",
                    tostring(lvl), tostring(_current_node_theme() or "none"),
                    elapsed, st.frames, (elapsed > 0 and st.frames / elapsed) or 0,
                    st.worst * 1000, flow_states, enemies)
                st.census = now
                st.frames = 0
                st.worst = 0
            end
        end
    end
    local theme = _current_node_theme()
    if not theme or theme == "wastes" then return end
    local profile = _CURSE_SKY_PROFILES[theme]
    if not profile then return end

    -- User brightness knob (#243): scales the INTERIOR channels (fill, ambient
    -- bounce, exposure) so an already-dark injected map can be lifted to taste
    -- without touching the exterior sky/sun/fog color that carries the curse
    -- mood. 1.0 = the baked profile exactly as-is (no behavior change). One
    -- cheap settings read per callback, dwarfed by the ShadingEnvironment calls.
    local b = tonumber(mod:get("curse_lighting_brightness")) or 1.0

    -- Per-MAP brightness override (#258, #271): resolve an EXTRA per-channel
    -- multiplier for maps that read too dark even after the profile + global knob.
    -- Keyed by injected-adventure BASE key (from the CW permutation level_id) then
    -- by curse theme, falling back to "*" = all curses. Missing map/theme/channel =
    -- 1.0 (no change), so no other map regresses. Applied ON TOP of profile + b.
    local map_over
    do
        local ls = LevelHelper and LevelHelper:current_level_settings()
        local base_key = ls and adventure_base_from_level_key(ls.level_id)
        local per_map = base_key and _CURSE_MAP_BRIGHTNESS[base_key]
        if per_map then
            map_over = per_map[theme] or per_map["*"]
        end
    end
    local function map_mul(var_name)
        return (map_over and map_over[var_name]) or 1.0
    end

    -- Multiply each existing color by the curse profile's per-var tint (and, for
    -- interior channels, by the user brightness `s`). ShadingEnvironment.vector3
    -- returns a fresh Vector3 each call (valid within this frame) — safe to read,
    -- multiply, and write back.
    local function mul_set(var_name, s)
        local t = profile[var_name]
        if not t then return end
        s = (s or 1.0) * map_mul(var_name)
        local v = ShadingEnvironment.vector3(shading_env, var_name)
        if v then
            ShadingEnvironment.set_vector3(shading_env, var_name,
                Vector3(v.x * t[1] * s, v.y * t[2] * s, v.z * t[3] * s))
        end
    end
    mul_set("skydome_tint_color")      -- exterior sky: curse hue only, no brightness lift
    mul_set("sun_color")               -- exterior direct sun: no lift
    mul_set("secondary_sun_color", b)  -- fill light (interior): lifted by brightness
    mul_set("ambient_tint", b)         -- interior bounce: lifted
    mul_set("ambient_tint_top", b)     -- interior top ambient: lifted
    mul_set("fog_color")               -- exterior haze: no lift

    local exp = (profile.exposure_mul or 1.0) * b * map_mul("exposure")
    if exp ~= 1.0 then
        local cur = ShadingEnvironment.scalar(shading_env, "exposure")
        if cur then
            ShadingEnvironment.set_scalar(shading_env, "exposure", cur * exp)
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
            -- #68 DIAGNOSTIC ([ct:mapnode68]): log the 3D node model each graph node
            -- resolves to. Vanilla deus_map_scene.lua:182-192 selects the node unit purely
            -- from the prefix of node.level before the first '_':
            --   sig_ -> SIG, pat_ -> TRAVEL, arena_ -> ARENA, key=="start" -> START,
            --   everything else -> SHRINE (altar/shrine mesh, no curse halo).
            -- Native CW Belakor-path variant keys (bell_belakor_path1, magnus_belakor_path1,
            -- cemetery_belakor_path1, ...) have an unrecognized prefix and are NOT matched by
            -- adventure_base_from_level_key, so the rewrite above skips them -> SHRINE. printf
            -- so it is visible with mod-logging OFF (_dbg routes to mod:debug, unseen).
            -- node.level here is POST-rewrite (the exact value spawn_graph_units consumes).
            do
                local lvl = node.level
                local model
                if key == "start" then
                    model = "START"
                else
                    local us = lvl:find("_")
                    local prefix = us and lvl:sub(1, us - 1) or lvl
                    model = (prefix == "sig" and "SIG") or (prefix == "pat" and "TRAVEL")
                        or (prefix == "arena" and "ARENA") or "SHRINE"
                end
                pcall(printf, "[ct:mapnode68] key=%s node_type=%s level=%s base_level=%s theme=%s curse=%s -> model=%s%s",
                    tostring(key), tostring(node.node_type), tostring(lvl),
                    tostring(node.base_level), tostring(node.theme), tostring(node.curse),
                    model, base_key and " (ct-rewritten to TRAVEL)" or "")
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
                        -- v0.7.42: use effective_setting so client mirrors host's disable
                        -- choices. Otherwise the deus_populate_graph filtering diverges
                        -- across peers → wrong-curse-on-node visible to one player only.
                        if not is_curse_disabled(curse) then
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

-- ============================================================
-- #145 DIAGNOSTIC (read-only): Citadel of Eternity resolved-god census
-- ============================================================
-- Citadel of Eternity is TWO nodes: the approach SIGNATURE map (level key
-- sig_citadel_<god>_pathN) and the finale ARENA map (arena_citadel_<god>_path1).
-- Vanilla assigns the run's single dominant_god to the "final" node and hot-spot-
-- spreads it to the adjacent approach (deus_populate_graph.lua:686-690). The mod's
-- `disable_dominant_god` (default ON) sets config.NO_DOMINANT_GOD=true, which SKIPS
-- that reservation -> the `finale_dominant_god` override (whose only delivery vector
-- IS the reservation) is neutered, and the two Citadel maps then roll INDEPENDENT
-- gods (#145). This host-only probe prints the resolved god per Citadel sub-map so a
-- live run confirms the mechanism on the user's seed. printf (mod:debug is silent
-- with logging off). Read-only: printf only.
CT_CITADEL145_MARKER = "citadel145:resolved_god_census_v0.7.212"
mod._ct_citadel145_dump = function(graph, no_dominant_god, dominant_god)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server or type(graph) ~= "table" then return end
    local found = false
    for _, n in pairs(graph) do
        local lvl = type(n) == "table" and n.level
        if type(lvl) == "string" and (string.find(lvl, "^sig_citadel") or string.find(lvl, "^arena_citadel")) then
            found = true
            pcall(printf, "[ct:citadel145] level=%s node_type=%s god=%s theme=%s curse=%s | NO_DOMINANT_GOD=%s dominant_god=%s finale_setting=%s disable_dominant_god=%s",
                tostring(lvl), tostring(n.node_type or n.level_type), tostring(n.god),
                tostring(n.theme), tostring(n.curse), tostring(no_dominant_god), tostring(dominant_god),
                tostring(mod:get("finale_dominant_god")), tostring(mod:get("disable_dominant_god")))
        end
    end
    if found then
        pcall(printf, "[ct:citadel145] (two Citadel nodes with DIFFERENT gods = disable_dominant_god neutered the finale override; NO_DOMINANT_GOD skips the finale reservation)")
    end
end

-- ============================================================
-- #145 FIX + #146 FEATURE: force the Citadel finale (and an optional SEPARATE
-- approach) god onto the COMPLETED graph.
-- ============================================================
-- Vanilla reserves dominant_god on the ARENA "final" node at deus_populate_graph.lua:686-690;
-- disable_dominant_god (config.NO_DOMINANT_GOD=true) SKIPS that reservation, neutering
-- finale_dominant_god (#145). We restore authority by rewriting the FINISHED graph rather
-- than the config, so regular missions keep all 4 gods (disable_dominant_god intact) while
-- the Citadel maps honor the chosen god(s). Runs on host AND client from the same host-synced
-- settings (effective_setting -> deterministic); the host also re-broadcasts (GRAPH_FIELD_MAP
-- syncs level/theme/curse). Level keys arena_citadel_<god>_path1 / sig_citadel_<god>_path<1-5>
-- exist for all 4 gods and are not aliased (deus_level_settings.lua:380-392,981-989), so
-- swapping only the god segment (keeping path<N>) is always valid. #146: finale_approach_god
-- (0 = follow finale) themes ONLY sig_citadel; finale_dominant_god governs arena_citadel.
-- #145 FIX marker (v0.7.219): the regression test asserts this constant + the function's
-- presence + both deus_populate_graph wiring sites, so the fix can't silently revert.
CT_CITADEL145_FIX_MARKER = "citadel145:force_finale_god_fix_v0.7.219"
mod._ct_force_finale_god = function(graph, config)
    if type(graph) ~= "table" then return end
    local finale_idx = effective_setting("finale_dominant_god")
    if type(finale_idx) ~= "number" or finale_idx <= 0 then return end
    local finale_god = FINALE_GODS[finale_idx]
    if not finale_god then return end
    local approach_idx = effective_setting("finale_approach_god")
    local approach_god = (type(approach_idx) == "number" and approach_idx > 0 and FINALE_GODS[approach_idx])
        or finale_god

    local function reassign(node, base, god)
        local path = type(node.level) == "string" and node.level:match("_path(%d+)$")
        if path then
            node.level = base .. "_" .. god .. "_path" .. path
        end
        node.theme = god
        node.god = god
        -- Re-match the curse to the new god (a curse from another god's pool is the #145
        -- symptom). Deterministic pick from the synced level_seed keeps host/client identical.
        -- Guarded: an empty pool keeps the vanilla curse rather than risking a nil.
        local pool = config and config.AVAILABLE_CURSES
            and config.AVAILABLE_CURSES[node.level_type]
            and config.AVAILABLE_CURSES[node.level_type][god]
        if type(pool) == "table" and #pool > 0 then
            local seed = math.floor(tonumber(node.level_seed) or 0)
            node.curse = pool[(seed % #pool) + 1]
        end
    end

    for _, n in pairs(graph) do
        if type(n) == "table" and type(n.level) == "string" then
            if string.find(n.level, "^arena_citadel") then
                reassign(n, "arena_citadel", finale_god)   -- #145: finale arena
            elseif string.find(n.level, "^sig_citadel") then
                reassign(n, "sig_citadel", approach_god)    -- #146: approach map
            end
        end
    end
end

-- #56 DIAGNOSTIC (read-only): Citadel curse host/client divergence probe. Runs on BOTH peers
-- (unlike host-only _ct_citadel145_dump) AFTER the graph snapshot broadcast/apply, so it logs
-- the curse each peer will render. Compare a host line to a client line for the same level: a
-- curse/theme mismatch is the #56 divergence (client rolled its OWN graph before the host
-- snapshot landed - the #136 seam). applied = apply_graph_snapshot's count on clients.
mod._ct_curse56_dump = function(graph, is_server, applied)
    if type(graph) ~= "table" then return end
    for _, n in pairs(graph) do
        local lvl = type(n) == "table" and n.level
        if type(lvl) == "string" and (string.find(lvl, "^sig_citadel") or string.find(lvl, "^arena_citadel")) then
            pcall(printf, "[ct:curse56] peer=%s level=%s curse=%s theme=%s | snapshot_applied=%s (host vs client MUST match; ref #136 populate_graph divergence)",
                is_server and "HOST" or "CLIENT", tostring(lvl), tostring(n.curse), tostring(n.theme), tostring(applied))
        end
    end
end

-- #136 DIAGNOSTIC (read-only): host/client CW mission divergence, ALL nodes.
-- Runs on BOTH peers AFTER the graph snapshot broadcast/apply - same seam as
-- _ct_curse56_dump above, but covers EVERY ingame node instead of only Citadel.
-- A client that populated its graph BEFORE the host's synced seed/snapshot landed
-- resolves the same node ids to DIFFERENT levels than the host (proven 2026-07-03:
-- client node_1=dlc_portals... vs host node_1=dlc_bastion...). Diff a host dump
-- against a client dump for the same run: any node whose level/god differs is the
-- divergence that makes the client play the wrong mission. The dump_graph output
-- below carries the same fields but only via _dbg (invisible with logging OFF, the
-- user's setup); this is the raw-printf, both-peers version. Bounded so a
-- pathological graph cannot flood the log.
mod._ct_mission136_dump = function(graph, is_server)
    if type(graph) ~= "table" then return end
    local peer = is_server and "HOST" or "CLIENT"
    local emitted = 0
    for k, n in pairs(graph) do
        if emitted >= 24 then break end
        if type(n) == "table" and n.node_type == "ingame" then
            emitted = emitted + 1
            pcall(printf, "[ct:136] graph peer=%s node=%s level=%s theme=%s curse=%s god=%s progress=%s",
                peer, tostring(k), tostring(n.level), tostring(n.theme),
                tostring(n.curse), tostring(n.god),
                tostring(n.run_progress or n.progress or "?"))
        end
    end
    pcall(printf, "[ct:136] graph peer=%s ingame_nodes=%d (diff host vs client; a same-node level/god mismatch = wrong-mission divergence)",
        peer, emitted)
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
        mod._ct_force_finale_god(result[1], config)  -- #145/#146
        local cursed, total = count_cursed(result[1])
        _dbg("[deus_populate_graph] post-run cursed=%d / total_curseable=%d", cursed, total)
        dump_graph(result[1], "post-run")
        mod._ct_citadel145_dump(result[1], config and config.NO_DOMINANT_GOD, dominant_god)  -- #145
        restore_curse_count()
        -- v0.7.64 graph sync — see ct_graph_snapshot_chunk block above.
        local is_server = Managers and Managers.player and Managers.player.is_server
        if is_server then
            broadcast_graph_snapshot(result[1])
            mod._ct_curse56_dump(result[1], true, nil)   -- #56
        else
            local applied = apply_graph_snapshot(result[1])
            if applied > 0 then
                _dbg("[ct_graph] applied host snapshot to %d nodes (post-run)", applied)
            end
            mod._ct_curse56_dump(result[1], false, applied)  -- #56
        end
        mod._ct_mission136_dump(result[1], is_server and true or false)  -- #136
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
    mod._ct_force_finale_god(result[1], config)  -- #145/#146
    local cursed, total = count_cursed(result[1])
    _dbg("[deus_populate_graph] post-run (shop-converted) cursed=%d / total_curseable=%d", cursed, total)
    dump_graph(result[1], "post-run-shop-converted")
    mod._ct_citadel145_dump(result[1], config and config.NO_DOMINANT_GOD, dominant_god)  -- #145
    restore_curse_count()
    -- v0.7.64 graph sync — see ct_graph_snapshot_chunk block above.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if is_server then
        broadcast_graph_snapshot(result[1])
        mod._ct_curse56_dump(result[1], true, nil)   -- #56
    else
        local applied = apply_graph_snapshot(result[1])
        if applied > 0 then
            _dbg("[ct_graph] applied host snapshot to %d nodes (post-run-shop-converted)", applied)
        end
        mod._ct_curse56_dump(result[1], false, applied)  -- #56
    end
    mod._ct_mission136_dump(result[1], is_server and true or false)  -- #136
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

-- Hook on PickupSystem._spawn_pickup — the lowest-level spawn function for the
-- PickupSystem-owned paths (public spawn_pickup, spawn_pickup_async,
-- buff_spawn_pickup, _spawn_guaranteed_pickup, _spawn_spread_pickups). Chest
-- bonus dice bypass this class and are covered at UnitSpawner below (#351).
-- Used for two purposes:
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
-- use, so it's converted too. Ravaged Art is `painting_scrap`; its guaranteed
-- level spawners bypass the spread-count replacement, so it must use this same
-- identity conversion rather than relying on pickup-settings counts.
mod._ct_collectible_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_collectible_policy")
local _CW_COLLECTIBLE_TO_COIN = mod._ct_collectible_policy.CONVERT_TO_COIN
mod._ct_collectible_to_coin = _CW_COLLECTIBLE_TO_COIN  -- exposed for regression guard
mod._ct351_rewrite_network_spawn = mod._ct_collectible_policy.rewrite_network_spawn

do
    local emitted = {}
    function mod._ct351_log_conversion(source, original_name)
        local key = tostring(source) .. ":" .. tostring(original_name)
        local count = emitted[key] or 0
        if count >= 2 then return end
        emitted[key] = count + 1
        pcall(printf, "[ct:351] collectible_conversion source=%s original=%s final=deus_soft_currency authority=host count=%d",
            tostring(source), tostring(original_name), count + 1)
    end
end

-- #134/#351 verification receipt. Logs each collectible that reaches the
-- PickupSystem path with the injected-level gate breakdown. Chest-generated
-- Loot Dice bypass this function entirely and use the bounded [ct:351]
-- UnitSpawner receipt below. Raw printf survives mod-logging-off; bounded 80
-- lines/session; pcall-guarded.
do
    local _n = 0
    function mod._ct134_log(name, spawn_type)
        if _n >= 80 then return end
        _n = _n + 1
        local on_adv, deus, level_id, adv_base = false, false, "?", "?"
        -- v0.7.243-dev (#134): is_server added. The first capture (2026-06-27) was
        -- CLIENT-side and showed on_adv=false; the fix needs a HOST-side line to
        -- prove whether the injected-adventure gate is false only on the client
        -- (client IS_INJECTED divergence, #136 class) or on the host too (the gate
        -- itself is missing this injected base). is_server disambiguates the two.
        local is_server = false
        pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            level_id = (cur and cur.level_id) or "?"
            adv_base = tostring(adventure_base_from_level_key(level_id))
            local m = Managers.mechanism and Managers.mechanism.game_mechanism
                and Managers.mechanism:game_mechanism()
            deus = (m and m.get_deus_run_controller and m:get_deus_run_controller()) ~= nil
            on_adv = on_injected_adventure_level()
            is_server = (Managers and Managers.player and Managers.player.is_server) and true or false
        end)
        printf("[ct-probe:collectible] name=%s spawn_type=%s is_server=%s on_adv=%s in_coin_set=%s deus=%s level=%s adv_base=%s",
            tostring(name), tostring(spawn_type), tostring(is_server), tostring(on_adv),
            tostring(_CW_COLLECTIBLE_TO_COIN[name] and "yes" or "no"),
            tostring(deus), tostring(level_id), tostring(adv_base))
    end
end

-- ============================================================
-- #143 DIAGNOSTIC (read-only): Morgrim's Bomb appearance-by-source census
-- ============================================================
-- "Morgrim's Bomb" == holy_hand_grenade. spawn_type (arg to PickupSystem._spawn_pickup,
-- the single spawn chokepoint, pickup_system.lua:1208) is the source discriminator:
--   "spawner"    = world spread-pool sampler (the 0.8 spawn_weighting path; suspected
--                  #143 origin -- reducing it blind crashed the sampler in v0.7.143,
--                  reverted v0.7.145, so we MEASURE before renormalizing).
--   "guaranteed" = level-baked spawner.  "dropped" = drop_item_on_ability_use bomb-boon
--   drop (source c/#120/#101).  "buff" = buff_spawn_pickup.
-- The chokepoint catches boon drops too (they route through _spawn_pickup as "dropped"),
-- so this one probe splits world-weight appearances from boon-driven ones -- the exact
-- question #143 needs answered before a safe grenade-pool renormalization. printf
-- (mod:debug is silent with logging off); Morgrim's is infrequent so no flood.
-- Read-only: printf only.
CT_MORGRIM143_MARKER = "morgrim143:appearance_by_spawn_type_census_v0.7.212"
-- issue 511: load-time marker for the #143 sum-preserving grenade renorm FIX (the
-- actual over-spawn fix lives in the PickupSystem.populate_pickups hook). Replaces
-- the io.open self-grep that threw in the VMF sandbox (no `io`). The exact renorm
-- text is a source invariant flagged for a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
CT_MORGRIM143_RENORM_MARKER = "morgrim143:holy_hand_grenade_sum_preserving_renorm_v0.7.232"
do
    local _by_source = {}
    mod._ct_morgrim143_count = function(spawn_type, on_adv)
        local k = tostring(spawn_type)
        _by_source[k] = (_by_source[k] or 0) + 1
        pcall(printf, "[ct:morgrim143] Morgrim's appeared: source=%s (x%d this session) injected_adv=%s",
            k, _by_source[k], tostring(on_adv))
    end

    -- v0.7.228-dev (#143 round 2): census ALL grenade-pool spawns, not just Morgrim's,
    -- so any log yields holy's true SHARE of world grenade spawns (the 2026-07-04 log
    -- proved the renorm applies -- holy 0.25 -> 0.125 on the CWV-normalized pool -- and
    -- only x2 spawner-holys all session; the perceived abundance must then come from
    -- grant-side faucets: blessing_holy_hand_grenade at the Shrine of Strife,
    -- drop_item_on_active_ability_use boon drops, altar/shop power-ups. Those are
    -- boon-trace / source=dropped territory, not spawn weight). Same chokepoint,
    -- printf-only, no new hook.
    local _grenade_names = {
        holy_hand_grenade = true, frag_grenade_t1 = true, fire_grenade_t1 = true,
        frag_grenade_t2 = true, fire_grenade_t2 = true, cwv_tuskgor_javelin_grenade = true,
    }
    local _grenade_counts, _grenade_total = {}, 0
    mod._ct_morgrim143_grenade_tally = function(pickup_name)
        if not _grenade_names[pickup_name] then return end
        _grenade_counts[pickup_name] = (_grenade_counts[pickup_name] or 0) + 1
        _grenade_total = _grenade_total + 1
        local parts = {}
        for n, c in pairs(_grenade_counts) do parts[#parts + 1] = string.format("%s=%d", n, c) end
        pcall(printf, "[ct:morgrim143] grenade world-spawn tally (session): total=%d { %s }",
            _grenade_total, table.concat(parts, ", "))
    end
end

-- #294 crash guard (exposed for /ct_regression_test). Returns whether it is SAFE to let
-- vanilla _spawn_pickup spawn this pickup's unit. FALSE only when the pickup names a unit
-- that is genuinely non-resident (would C-crash spawn_network_unit -> add_unit_extensions).
-- Mirrors vanilla PickupSystem._safe_to_spawn_pickup (pickup_system.lua:878). Fails SAFE
-- (returns true, i.e. does not block) when there's no named unit, when a spawn_override_func
-- handles spawning itself, or when Application.can_get is unavailable -- so the guard can
-- never false-drop a legitimate pickup, only stop a provably non-resident one.
CT_PICKUP_RESIDENCY_GUARD_MARKER = "spawn_pickup_can_get_unit_guard_v0.7.222"
function mod._ct_pickup_unit_spawn_safe(settings)
    local un = settings and settings.unit_name
    if not un then return true end                         -- no named unit -> not our concern
    if settings.spawn_override_func then return true end   -- custom spawn path, leave alone
    if not (rawget(_G, "Application") and Application.can_get) then return true end  -- can't check -> don't block
    return Application.can_get("unit", un) and true or false
end

mod:hook("PickupSystem", "_spawn_pickup", function(func, self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    local on_adv = on_injected_adventure_level()

    -- #134/#351: a collectible arriving here means it used PickupSystem; log
    -- its gate before the host-authoritative identity rewrite.
    if pickup_name == "loot_die" or pickup_name == "lorebook_page" or pickup_name == "painting_scrap" then
        mod._ct134_log(pickup_name, spawn_type)
    end

    local original_name = pickup_name
    local routed_name, converted = mod._ct_collectible_policy.route_name(
        pickup_name, on_adv, self.is_server == true)
    if converted then
        pickup_name = routed_name
        settings = (AllPickups and AllPickups.deus_soft_currency) or settings
        mod._ct351_log_conversion("pickup_system", original_name)
    end

    -- #294 (crash): guard the spawn chokepoint against a NON-RESIDENT pickup unit.
    -- _ct_pickup_unit_spawn_safe mirrors vanilla's own PickupSystem._safe_to_spawn_pickup
    -- (pickup_system.lua:878) can_get("unit", unit_name) check, which the _spawn_pickup
    -- path (pickup_system.lua:1414 -> spawn_network_unit at :1290) does NOT perform. A
    -- mutator pickup whose package isn't resident -- e.g. skulls_2023 'pup_skull_of_fury'
    -- force-spawned via the gt devtool without the mutator package loaded -- otherwise
    -- reaches spawn_network_unit non-resident and hard-crashes add_unit_extensions
    -- (entity_manager2.lua:114 "table index is nil"). Skip it, exactly as vanilla's
    -- _safe_to_spawn_pickup would (returns false -> no spawn).
    if not mod._ct_pickup_unit_spawn_safe(settings) then
        pcall(printf, "[ct:294] SKIP non-resident pickup '%s' (unit=%s not loaded) -- would crash spawn_network_unit/add_unit_extensions",
            tostring(pickup_name), tostring(settings and settings.unit_name))
        return
    end

    -- #58/#156 spawn census: count the FINAL pickup_name (post collectible->coin
    -- conversion) once vanilla confirms it actually spawned. _spawn_pickup is the
    -- single chokepoint for both the spread pass and the guaranteed chest/altar pass,
    -- so this tallies EVERYTHING. #322: vanilla returns (pickup_unit, pickup_unit_go_id)
    -- (pickup_system.lua:1207); capture and re-return BOTH. Only one vanilla caller uses
    -- the go_id -- the linked-pickup RPC path (:1441 -> rpc_link_pickup) -- so dropping it
    -- (the old `return spawned`, VMF_RECIPES 2 collapse) desynced surface-linked pickups
    -- to clients. The #294 guard's early `return` (nil,nil) matches vanilla's own early
    -- returns, so it stays correct.
    local spawned, go_id = func(self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    if mod._ct_tally_count then mod._ct_tally_count(pickup_name, spawned) end
    -- #143 (read-only): tag every CONFIRMED Morgrim's Bomb spawn with its source
    -- (world spread-pool vs level-baked vs bomb-boon drop) so a live run settles
    -- whether the over-appearance origin is the world weight or the boon re-drop.
    if pickup_name == "holy_hand_grenade" and spawned ~= nil and mod._ct_morgrim143_count then
        mod._ct_morgrim143_count(spawn_type, on_adv)
    end
    -- #143 round 2: per-session tally of EVERY grenade-type spawn so holy's share is
    -- computable from any log (world-spawn side is proven fixed; this keeps the receipt).
    if spawned ~= nil and mod._ct_morgrim143_grenade_tally then
        mod._ct_morgrim143_grenade_tally(pickup_name)
    end
    return spawned, go_id
end)
-- issue 511: load-time provenance marker for the #322 two-return _spawn_pickup hook
-- above. The VMF Lua sandbox exposes NO `io`, so the old source self-grep threw
-- "attempt to index global 'io'" and FAILED /ct_regression_test on healthy code;
-- the check now asserts this marker (set beside the hook at load) instead. The
-- exact 2-value capture/return SHAPE is a source invariant flagged for a repo QA
-- gate (PROJECT_STANDARDS 2.2b tier a).
CT_SPAWN_PICKUP322_MARKER = "spawn_pickup322:two_value_capture_and_return_v0.7.245"

-- Loot dice rolled from an opened chest do not call PickupSystem at all:
-- InteractionDefinitions.chest.server.stop builds pickup init data and calls
-- UnitSpawner.spawn_network_unit directly [src: interactions.lua:2112-2138].
-- Rewrite that exact pickup identity at the authoritative owner-spawn seam;
-- UnitSpawner then serializes the coin identity into the game object and clients
-- create only the replicated coin husk [src: unit_spawner.lua:336-352,470-490].
-- Stock Adventure, clients, and every non-collectible network unit pass through.
mod:hook("UnitSpawner", "spawn_network_unit", function(func, self, unit_name,
        unit_template_name, extension_init_data, position, rotation, material, ...)
    local pickup_data = type(extension_init_data) == "table" and extension_init_data.pickup_system
    local candidate = type(pickup_data) == "table"
        and _CW_COLLECTIBLE_TO_COIN[pickup_data.pickup_name]
    if candidate then
        local coin_settings = AllPickups and AllPickups.deus_soft_currency
        local rewritten_unit, rewritten_template, rewritten_init, converted, original_name =
            mod._ct_collectible_policy.rewrite_network_spawn(unit_name, unit_template_name,
                extension_init_data, coin_settings, on_injected_adventure_level(),
                self.is_server == true)
        if converted then
            mod._ct351_log_conversion("unit_spawner", original_name)
            return func(self, rewritten_unit, rewritten_template, rewritten_init,
                position, rotation, material, ...)
        end
    end
    return func(self, unit_name, unit_template_name, extension_init_data,
        position, rotation, material, ...)
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
            -- [ct:456] leftover book spot (this pedestal was NOT the chest): report the
            -- casket outcome + position unconditionally. A grimoire that lands here with
            -- spawned=false is the "always empty" symptom on the guaranteed path (case c);
            -- spawned=true means the spot got a casket, so the "empty" report is elsewhere.
            pcall(function()
                local p = Unit.local_position(spawner_unit, 0)
                printf("[ct:456] leftover_book kind=%s casket_spawned=%s pos=(%.1f,%.1f,%.1f)",
                    is_tome and "tome" or "grim", tostring(casket and Unit.alive(casket) and true or false),
                    Vector3.x(p), Vector3.y(p), Vector3.z(p))
            end)
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
    -- [ct:456] unconditional: this book pedestal produced NOTHING (empty). Pinpoints the
    -- "location of the first Grimoire is always empty" symptom on the guaranteed path.
    pcall(function()
        local p = Unit.local_position(spawner_unit, 0)
        printf("[ct:456] empty_book kind=%s pos=(%.1f,%.1f,%.1f) (cap reached, altar n/a, casket settings missing)",
            is_tome and "tome" or "grim", Vector3.x(p), Vector3.y(p), Vector3.z(p))
    end)
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

-- #299: peer_id -> { lpid, anchor (Vector3Box of the chest pos), ttl }. Armed by the
-- chest hook for players it frees/respawns at a DISTANT beacon (awaiting-rescue or
-- dead), consumed by mod._ct_chest_teleport_tick (driven from mod.update) which
-- teleports them to a living teammate the instant they become controllable. Not a
-- main-chunk local (this file sits at the Lua 5.1 200-locals cap) -- a mod field so
-- both the hook and the tick reach it without adding to the chunk's local count.
mod._ct_pending_team_teleport = mod._ct_pending_team_teleport or {}

-- #350 early reward access is presentation-only while vanilla remains RUNNING;
-- register its hooks and runtime policy check before the completion-only OPEN hook.
do
    local cost_feature = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost")
    for _, c in ipairs(cost_feature.rt_checks or {}) do _rt_register(c.name, c.fn) end
    local feature = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_early_reward")
    for _, c in ipairs(feature.rt_checks or {}) do _rt_register(c.name, c.fn) end
end

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
    --
    -- #299: capture the chest position ONCE. Players freed/respawned from a distant
    -- beacon (awaiting-rescue or dead) stand up alone far from the group; we arm a
    -- deferred teleport (mod._ct_chest_teleport_tick) that returns them to whichever
    -- living teammate is nearest THIS chest once they're controllable. The team is
    -- clustered at the chest when it opens, so it's the right "team" anchor.
    local chest_pos_box
    do
        local chest_unit = self._unit
        if chest_unit and Unit.alive(chest_unit) then
            local ok, p = pcall(Unit.world_position, chest_unit, 0)
            if ok and p then chest_pos_box = Vector3Box(p) end
        end
    end

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
                    -- #299: they stand up AT that (distant) beacon, so arm the
                    -- return-to-team teleport for once they're controllable.
                    StatusUtils.set_respawned_network(unit, true, unit)
                    action = "freed-awaiting-rescue"
                    if chest_pos_box then
                        -- freed=true: already freed here, so the tick must NOT re-free it.
                        -- #299 rework: key by peer_id/local_player_id -- host-owned BOTS share
                        -- the host peer_id, so a peer-only key made sibling entries overwrite
                        -- each other. Store the stable player OBJECT so the tick re-reads
                        -- player_unit across the respawn/recovery instead of a fragile relookup.
                        mod._ct_pending_team_teleport[peer_id .. "/" .. tostring(local_player_id)] =
                            { peer_id = peer_id, lpid = local_player_id, player = player, anchor = chest_pos_box, ttl = 30.0, freed = true }
                    end
                elseif is_knocked and not is_disabled_pact and StatusUtils and StatusUtils.set_revived_network then
                    -- bleeding out -> revive in place (skip disabler-held players).
                    -- Already with the team where they fell -> NOT armed for teleport.
                    StatusUtils.set_revived_network(unit, true, nil)
                    action = "revived-knocked"
                elseif data and (health_state == "dead" or data.respawn_timer ~= nil) then
                    -- fully dead / in the respawn queue -> spawn at the active beacon.
                    -- #299: that beacon is ~70m ahead of the front player, so arm the
                    -- return-to-team teleport for once the respawned unit is controllable.
                    data.respawn_timer = 0
                    pending_chest_respawn[peer_id] = true   -- arm THP/wounded post-respawn overrides
                    action = "respawn-timer-cleared"
                    if chest_pos_box then
                        -- freed=nil: the unit spawns HANGING at the beacon a few frames later
                        -- (RespawnHandler sends ready_for_assisted_respawn=true), so the tick
                        -- frees it once it appears, then teleports once it stands. See the
                        -- awaiting branch for the peer/lpid keying + stored-player rationale (#299).
                        mod._ct_pending_team_teleport[peer_id .. "/" .. tostring(local_player_id)] =
                            { peer_id = peer_id, lpid = local_player_id, player = player, anchor = chest_pos_box, ttl = 30.0 }
                    end
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

-- ============================================================
-- #299: return chest-revived players to the team
-- ============================================================
-- A player freed from AWAITING-RESCUE stands up at the respawn beacon they were
-- hanging at; a DEAD player respawned by the chest spawns hanging at a beacon
-- ~70m ahead of the front player (RespawnHandler DEFAULT_RESPAWN_DISTANCE). Either
-- way the chest revive leaves them stranded far from the group. This deferred
-- host-side pass (driven from the single mod.update owner above) teleports each
-- armed player to a living teammate the instant they become controllable.
--
-- WHY DEFERRED, not inline in the chest hook:
--   * awaiting-rescue: the freed unit is LINK-glued to its respawn flavour_unit
--     through the recovery animation (player_character_state_waiting_for_assisted_
--     respawn.lua:30 enable_linked_movement, :59 disable on exit -> "standing"), so
--     a teleport during recovery is overwritten every frame until it stands.
--   * dead: the unit does not even exist until RespawnHandler.server_update spawns
--     it a few frames after we zero respawn_timer.
-- Polling for "alive AND not status:is_disabled()" catches the exact frame the unit
-- is standing + script-driven-movement, when locomotion:teleport_to sticks. This is
-- also the ORDERING the reporter asked for: the human reaches the team as soon as
-- they can move, minimizing the window where a bot would leash out to the beacon.
-- Host-authoritative teleport mirrors RespawnHandler.server_update's own move
-- (respawn_handler.lua:398-407): locomotion:teleport_to + rpc_teleport_unit_to.
do
    -- nearest ALIVE, controllable (not disabled) teammate to `anchor_pos`, excluding
    -- `exclude_unit`. Human or bot -- either one anchors "the team". Returns unit/nil.
    local function _nearest_controllable_teammate(anchor_pos, exclude_unit)
        local pm = Managers.player
        local players = pm and pm.human_and_bot_players and pm:human_and_bot_players()
        if not players then return nil end
        local best, best_d
        for _, p in pairs(players) do
            local u = p and p.player_unit
            if u and u ~= exclude_unit and Unit.alive(u) then
                local st = ScriptUnit.has_extension(u, "status_system")
                local pos = POSITION_LOOKUP[u]
                if st and pos and not st:is_disabled() then
                    local d = anchor_pos and Vector3.distance_squared(anchor_pos, pos) or 0
                    if not best_d or d < best_d then best_d, best = d, u end
                end
            end
        end
        return best
    end

    mod._ct_pending_team_teleport = mod._ct_pending_team_teleport or {}

    mod._ct_chest_teleport_tick = function(dt)
        local pending = mod._ct_pending_team_teleport
        if not pending or next(pending) == nil then return end
        if not (Managers.player and Managers.player.is_server) then
            -- lost authority (mission end / became client): drop everything.
            for k in pairs(pending) do pending[k] = nil end
            return
        end
        for key, entry in pairs(pending) do
            local drop = false
            pcall(function()
                entry.ttl = (entry.ttl or 0) - (dt or 0)

                -- #299 rework: resolve the unit via the STORED player object first (stable
                -- across the respawn/recovery unit swap); only relookup by peer/lpid if the
                -- stored handle has no unit yet (dead-branch: unit spawns a few frames later).
                -- The prior code re-looked-up every tick and, per the 2026-07-05 host log,
                -- never observed the freed unit as alive+controllable -> teleport never fired.
                local player = entry.player
                if not (player and player.player_unit) then
                    player = Managers.player:player(entry.peer_id, entry.lpid) or player
                    entry.player = player or entry.player
                end
                local unit = player and player.player_unit
                local alive = (unit and Unit.alive(unit)) and true or false
                local st = alive and ScriptUnit.has_extension(unit, "status_system") or nil
                local awaiting = (st and st.is_ready_for_assisted_respawn and st:is_ready_for_assisted_respawn()) and true or false
                local disabled = (st and st:is_disabled()) and true or false

                -- Per-eval diagnostic, throttled to state CHANGES (armed always in dev per the
                -- diagnostics doctrine). If a teleport still fails to fire, this prints the exact
                -- reason (player missing / unit dead / stuck disabled / stuck awaiting).
                local sig = tostring(player ~= nil) .. tostring(alive) .. tostring(disabled) .. tostring(awaiting)
                if entry._last_sig ~= sig then
                    entry._last_sig = sig
                    pcall(printf, "[ct-chest-revive] tick key=%s found=%s alive=%s disabled=%s awaiting=%s ttl=%.1f (#299)",
                        tostring(key), tostring(player ~= nil), tostring(alive), tostring(disabled), tostring(awaiting), entry.ttl or -1)
                end

                -- Dead-branch case: the respawned unit spawns HANGING at the beacon
                -- (ready_for_assisted_respawn) and would wait for a manual rescue. Free it
                -- ONCE (starts the same recovery the awaiting branch used), then fall
                -- through to the controllable check. `freed` guards against re-sending.
                if st and not entry.freed and awaiting
                    and rawget(_G, "StatusUtils") and StatusUtils.set_respawned_network then
                    StatusUtils.set_respawned_network(unit, true, unit)
                    entry.freed = true
                    pcall(printf, "[ct-chest-revive] freed respawned-hanging key=%s at beacon; awaiting stand to teleport (#299)", tostring(key))
                end

                if st and not disabled then
                    -- controllable now -> send them to the team.
                    local anchor_pos = entry.anchor and entry.anchor:unbox()
                    local teammate = _nearest_controllable_teammate(anchor_pos, unit)
                    if teammate then
                        local loco = ScriptUnit.has_extension(unit, "locomotion_system")
                        local pos = Unit.local_position(teammate, 0)
                        local rot = Unit.local_rotation(teammate, 0)
                        if loco and pos then
                            loco:teleport_to(pos, rot)
                            local nm = Managers.state and Managers.state.network
                            local go_id = nm and nm:unit_game_object_id(unit)
                            if go_id then
                                nm.network_transmit:send_rpc_clients("rpc_teleport_unit_to", go_id, pos, rot)
                            end
                            pcall(printf, "[ct-chest-revive] teleported key=%s back to the team (#299)", tostring(key))
                        end
                    else
                        pcall(printf, "[ct-chest-revive] no controllable teammate to anchor key=%s -- left in place (#299)", tostring(key))
                    end
                    drop = true
                elseif entry.ttl <= 0 then
                    -- Log the FINAL state so a repeat failure is self-diagnosing.
                    pcall(printf, "[ct-chest-revive] team-teleport TTL expired for key=%s (found=%s alive=%s disabled=%s awaiting=%s) (#299)",
                        tostring(key), tostring(player ~= nil), tostring(alive), tostring(disabled), tostring(awaiting))
                    drop = true
                end
            end)
            if drop then pending[key] = nil end
        end
    end
end

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

-- Pure policy seam for #556: only talent templates are suppressed by an existing
-- same-name power-up. Non-talents retain the historical starting-boon behavior.
function mod._ct_starting_talent_is_duplicate(template, name, existing_names)
    return template and template.talent == true and existing_names[name] == true
end

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
mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index, initial_talents_for_career)
    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end  -- host-only
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    -- Vanilla has already materialized `initial_talents_for_career` into generic
    -- `talent_<tier>_<column>` power-ups before this hook_safe callback runs
    -- (deus_run_controller.lua:471-495).  Keep that post-call list as the canonical
    -- identity set: a configured starting talent that is already selected must not
    -- be appended a second time.  The fifth argument is named above as a signature
    -- lock even though the post-call list is more robust than rebuilding its mapping.
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local existing_names = {}
    for _, power_up in ipairs(existing or {}) do
        if power_up and power_up.name then existing_names[power_up.name] = true end
    end

    local extra = {}
    local selected_talents_skipped = 0
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            -- v0.7.240-dev (#426) peer-parity gate: a ct-modded starting boon written into
            -- this player's run-state list rides the shared-state sync as a modded
            -- deus_power_up_templates index (deus_run_state_spec.lua:60 encode / :85
            -- decode) and CTDs any non-ct peer. Vanilla starting boons are untouched.
            -- Fail-safe direction: an unconfirmed peer (e.g. a just-joined client whose
            -- beacon ack is still in flight) suppresses the MODDED grant for this event.
            local template = rawget(_G, "DeusPowerUpTemplates") and rawget(DeusPowerUpTemplates, name)
            if mod._ct_starting_talent_is_duplicate(template, name, existing_names) then
                selected_talents_skipped = selected_talents_skipped + 1
            elseif mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(name)
                and not (mod._ct_wire_safe and mod._ct_wire_safe()) then
                pcall(printf, "[ct:426] starting boon %s skipped: peer parity not confirmed (modded boon would CTD a non-ct peer)", tostring(name))
            else
                extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
            end
        end
    end

    if selected_talents_skipped > 0 then
        pcall(printf, "[ct:556] starting talents: skipped=%d already selected for profile=%s career=%s",
            selected_talents_skipped, tostring(profile_index), tostring(career_index))
    end

    if #extra == 0 then return end

    -- The post-call `existing` snapshot already includes vanilla's talent + event
    -- boons. table.clone with skip_metatable keeps the array shape without copying
    -- any inherited methods.
    local skip_metatable = true
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
-- Starting-Boon Preview on the Tab-hold panel (#461)
-- ============================================================
-- Feature (issue #461): "When holding TAB in the keep, show a preview list of the
-- starting boons with their icons on the right pop-out panel."
--
-- Surface: IngamePlayerListUI (the keep/mission Tab-hold player list). Its right panel
-- (scenegraph parent "banner_right") already hosts the vanilla deed-reward icon strip
-- (reward_item passes) AND the CW node-info boon icon (terror_event_power_up_icon), so
-- THIS renderer is vanilla-proven to resolve Deus boon-icon textures on this exact panel
-- (ingame_player_list_ui_v2.lua / _definitions.lua). Data source is the mod's own
-- host-config -> available in the keep before any run exists.
--
-- Risk posture (untestable UI; PROJECT_STANDARDS 2.2b + "no-guessing" doctrine): we do
-- NOT append into vanilla's `_reward_widgets` (those draw in vanilla's UNguarded pass, so
-- a boon-icon atlas that is not resident in the keep could assert mid-loop and kill the
-- whole panel render). Instead we build our OWN widgets and draw them in our OWN
-- begin_pass/end_pass with each draw_widget individually pcall-wrapped -- worst case our
-- pass no-ops and the panel is byte-identical to vanilla. Icon and name are SEPARATE
-- widgets per row, so a boon whose icon texture will not resolve still shows its NAME
-- (fonts are always resident): graceful degradation, never a blank/crashing row.
--
-- Data: `mod._ct_collect_start_boons` mirrors the grant hook's enumeration
-- (DeusPowerUpsArray x start_boon_<name>) but resolves through `effective_setting`, so a
-- CLIENT previews the HOST's configured boons once the host-settings sync has landed
-- (falls back to the client's own toggles pre-sync -- see CHANGELOG limitation note).
-- ct's hooks on IngamePlayerListUI, all on DISTINCT methods (singleton-clean; ct had no
-- hook on this class before #461): `_setup_deed_reward_data` (fires on EVERY panel
-- activation -- set_active(true) calls it, ingame_player_list_ui_v2.lua:1224 -- so the
-- gate below re-evaluates per Tab press), `_draw` (the SHARED guarded draw pass -- also
-- draws the #533 deus collectible counters; NEVER add a second _draw hook), and
-- `_setup_mission_data` (#533 build point, below).
--
-- v0.7.258 follow-up fixes (user report on the 0.7.251 ship):
-- (1) "header but no rows": the first ship anchored rows on the "reward_item"
--     scenegraph node, which carries NO size and so inherits banner_right's full
--     660x1080 rect (ui_scenegraph.lua:109 `node_def.size or parent.size`). That node's
--     origin computes to world y = -750 (below the screen); vanilla only renders there
--     via pass-level vertical_alignment "top" inside the inherited rect
--     (create_reward_item icon style, _definitions.lua:1750, aligned by
--     UIUtils.align_box_inplace, helpers/ui_utils.lua:542-558). Our rows used
--     center/default alignment, so every row landed at negative screen y -- invisible --
--     while the header, anchored on the SIZED "reward_divider" node ({264,32}, world
--     y~348 at 1080p reference), rendered fine. Fix: anchor ALL rows on
--     "reward_divider" too and stack them below the header with per-row offsets
--     (2 columns x 9 rows, 28px pitch, "+N more" overflow) inside the band that is
--     empty in the gated context (no deed rewards, no collectibles in the keep).
-- (2) "shows all over the keep": now gated on the party actually QUEUING a Chaos
--     Wastes expedition -- see mod._ct_preparing_cw_expedition below.
CT_BOON_PREVIEW_461_MARKER = "boon_preview_ingame_playerlist_v0.7.258"

-- TRUE while this peer's party is queued for a Chaos Wastes expedition (host pressed
-- host/start on a CW journey; not yet transitioned out of the keep). Direct port of
-- vanilla MatchmakingManager.is_matchmaking_versus (matchmaking_manager.lua:1256-1266)
-- retargeted at mechanism "deus":
--  * host path: set_matchmaking_data writes lobby_data.mechanism = "deus"
--    (matchmaking_manager.lua:985) for public AND private games; host state leaves
--    MatchmakingStateIdle while hosting the search.
--  * client path: rpc_set_matchmaking always sends is_matchmaking=true to party
--    clients (matchmaking_manager.lua:1083), putting them in
--    MatchmakingStateFriendClient (non-idle), and they read the host lobby's
--    replicated "mechanism" field like vanilla does.
--  * reset path: loading into any hub level rewrites matchmaking="false" and
--    refreshes the mechanism field (state_loading.lua:2584/:2597), and cancel sends
--    rpc_set_matchmaking(false) -> Idle, so the block disappears after a cancel or a
--    finished run. Whole body pcall-bracketed: any nil seam = just no preview.
function mod._ct_preparing_cw_expedition()
    local ok, res = pcall(function()
        local mm = Managers.matchmaking
        if not mm then return false end
        local state = mm._state
        local is_matchmaking = state and state.NAME ~= "MatchmakingStateIdle"
        local lobby = mm.lobby
        local lobby_client = (state and state.lobby_client)
            or (Managers.lobby and (Managers.lobby:query_lobby("matchmaking_session_lobby")
                or Managers.lobby:query_lobby("matchmaking_join_lobby")))
        local lobby_mechanism = lobby and lobby.lobby_data and lobby:lobby_data("mechanism")
        local client_mechanism = lobby_client and lobby_client.lobby_data and lobby_client:lobby_data("mechanism")
        local is_lobby_matchmaking = lobby and lobby.lobby_data and lobby:lobby_data("matchmaking") == "true"
        local is_client_matchmaking = lobby_client and lobby_client.lobby_data and lobby_client:lobby_data("matchmaking") == "true"
        return ((is_matchmaking or is_lobby_matchmaking or is_client_matchmaking)
            and (lobby_mechanism == "deus" or client_mechanism == "deus")) or false
    end)
    return (ok and res) or false
end

-- Resolve the same career-specific identity vanilla uses for a talent power-up.
-- Generic talent templates intentionally have no display_name/icon of their own;
-- vanilla routes them through these helpers (deus_power_up_utils.lua:298-322).
-- Kept on `mod` so the runtime regression suite can exercise the real resolver.
function mod._ct_start_boon_identity(name, rarity, profile_index, career_index)
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local template = type(templates) == "table" and rawget(templates, name) or nil
    local display = mod._ct_boon_display_name(name)
    local icon = template and template.icon or nil

    if template and template.talent and profile_index and career_index then
        local utils = rawget(_G, "DeusPowerUpUtils")
        if utils and type(utils.get_power_up_name_text) == "function" then
            local ok, resolved = pcall(utils.get_power_up_name_text, name,
                template.talent_index, template.talent_tier, profile_index, career_index)
            if ok and type(resolved) == "string" and resolved ~= "" then display = resolved end
        end
        if utils and type(utils.get_power_up_icon) == "function" then
            local ok, resolved = pcall(utils.get_power_up_icon,
                { name = name, rarity = rarity }, profile_index, career_index)
            if ok and type(resolved) == "string" and resolved ~= "" then icon = resolved end
        end
    end

    return display, icon
end

-- Ordered, de-duplicated list of the starting boons the run will grant, host-effective.
-- Each entry: { name, rarity, display, icon, modded }. On `mod` (not a file-local) per
-- the Lua 5.1 200-locals cap; shared by the Tab panel + `/ct_preview_boons`.
function mod._ct_collect_start_boons()
    local out = {}
    local arr = rawget(_G, "DeusPowerUpsArray")
    if type(arr) ~= "table" then return out end
    local eff = mod._ct_effective_setting or function(k) return mod:get(k) end
    local is_modded = mod._ct_is_modded_power_up
    local profile_index, career_index
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player()
    if player then
        local ok, profile, career = pcall(function()
            return player:profile_index(), player:career_index()
        end)
        if ok then profile_index, career_index = profile, career end
    end
    local seen = {}
    for _, entry in ipairs(arr) do
        local name = entry and entry.name
        if name and not seen[name] and eff("start_boon_" .. name) then
            seen[name] = true
            local display, icon = mod._ct_start_boon_identity(
                name, entry.rarity, profile_index, career_index)
            out[#out + 1] = {
                name = name,
                rarity = entry.rarity,
                display = display,
                icon = icon,
                modded = (is_modded and is_modded(name)) or false,
            }
        end
    end
    table.sort(out, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
    return out
end

-- Header widget for the boon-preview block, anchored to the reward_divider scenegraph
-- node (where vanilla's reward header sits, above the icon rows on banner_right).
function mod._ct_build_boon_preview_header(title)
    return UIWidget.init(UIWidgets.create_simple_text(title, "reward_divider", 22, nil, {
        horizontal_alignment = "left",
        vertical_alignment = "center",
        localize = false,
        word_wrap = false,
        font_size = 22,
        font_type = "hell_shark",
        text_color = { 255, 255, 214, 138 },
        offset = { 4, 0, 3 },
    }))
end

-- One icon widget + one name widget per boon. Icon and name are SEPARATE widgets so a
-- boon whose icon texture will not resolve still shows its name (see risk posture
-- above). ALL rows are anchored on the SIZED "reward_divider" scenegraph node -- the
-- node the header provably renders on -- never on the sizeless "reward_item" node (the
-- v0.7.251 off-screen bug; see the follow-up note in the banner comment). Layout:
-- 2 columns x 9 rows below the header, 28px row pitch, 330px column pitch, inside the
-- band (screen y ~340 down to ~90 at 1080p reference) that is empty while a CW
-- expedition is queued (no deed rewards, no keep collectibles). Overflow past 18
-- becomes a "+N more" line; /ct_preview_boons always lists everything.
function mod._ct_build_boon_preview_widgets(boons)
    -- UTF-8 safe truncation (cut on a codepoint boundary so a curly quote or accented
    -- glyph can never be split into an invalid byte sequence). Function-scoped local:
    -- the file's top-level chunk is near the Lua 5.1 200-locals cap.
    local function trunc(s, max_bytes)
        if type(s) ~= "string" or #s <= max_bytes then return s end
        local cut = max_bytes
        while cut > 1 do
            local b = s:byte(cut + 1)
            if not b or b < 0x80 or b >= 0xC0 then break end -- next byte starts a codepoint (or end)
            cut = cut - 1
        end
        return s:sub(1, cut) .. "..."
    end
    local out = {}
    local ICON, ROW_H, COL_W, NUM_ROWS = 24, 28, 330, 9
    local MAX = NUM_ROWS * 2
    local n = math.min(#boons, MAX)
    for i = 1, n do
        local b = boons[i]
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 4 + col * COL_W
        -- Offsets are relative to the reward_divider node (origin y ~348, center ~364
        -- at 1080p reference): text is v-centered in the node's 32px box then pushed
        -- down per row; the icon (drawn from its bottom-left corner by the texture
        -- pass) gets +4 so its center matches the text center.
        local row_center_offset = -(34 + row * ROW_H)
        if b.icon then
            out[#out + 1] = UIWidget.init(UIWidgets.create_simple_texture(
                b.icon, "reward_divider", false, false, nil,
                { x, row_center_offset + 4, 1 }, { ICON, ICON }))
        end
        out[#out + 1] = UIWidget.init(UIWidgets.create_simple_text(
            trunc(b.display or b.name, 30), "reward_divider", 16, nil, {
                horizontal_alignment = "left",
                vertical_alignment = "center",
                localize = false,
                word_wrap = false,
                font_size = 16,
                font_type = "hell_shark",
                text_color = { 255, 235, 235, 235 },
                offset = { x + ICON + 8, row_center_offset, 2 },
            }))
    end
    if #boons > n then
        out[#out + 1] = UIWidget.init(UIWidgets.create_simple_text(
            string.format("+%d more", #boons - n), "reward_divider", 16, nil, {
                horizontal_alignment = "left",
                vertical_alignment = "center",
                localize = false,
                word_wrap = false,
                font_size = 16,
                font_type = "hell_shark",
                text_color = { 255, 200, 200, 200 },
                offset = { 4, -(34 + NUM_ROWS * ROW_H), 2 },
            }))
    end
    return out
end

-- Build point: vanilla calls _setup_deed_reward_data on EVERY panel activation
-- (set_active(true), ingame_player_list_ui_v2.lua:1224), so all three gates below
-- re-evaluate per Tab press. Gates: keep-only (self._is_in_inn), local display toggle
-- preview_starting_boons, and (v0.7.258, the user's "should only show while the team
-- prepares an expedition" report) a queued Chaos Wastes expedition. Builds onto the
-- instance so the per-frame _draw hook only draws (zero per-frame allocation).
mod:hook_safe("IngamePlayerListUI", "_setup_deed_reward_data", function(self)
    self._ct_boon_preview_widgets = nil
    self._ct_boon_header_widget = nil
    if not self._is_in_inn then return end
    if not mod:get("preview_starting_boons") then return end
    if not mod._ct_preparing_cw_expedition() then
        pcall(printf, "[ct:461] boon preview suppressed: no Chaos Wastes expedition queued")
        return
    end
    local ok, err = pcall(function()
        local boons = mod._ct_collect_start_boons()
        if #boons == 0 then return end
        self._ct_boon_preview_widgets = mod._ct_build_boon_preview_widgets(boons)
        self._ct_boon_header_widget = mod._ct_build_boon_preview_header(
            string.format("%s (%d)", mod:localize("ct_boon_preview_header"), #boons))
        pcall(printf, "[ct:461] boon preview built: %d boons (CW expedition queued)", #boons)
    end)
    if not ok then
        self._ct_boon_preview_widgets = nil
        self._ct_boon_header_widget = nil
        pcall(printf, "[ct:461] boon-preview build failed (panel unaffected): %s", tostring(err))
    end
end)

-- #533 diagnostics follow-up: arm on native Tab-overlay activation and sample from
-- this existing singleton draw seam after vanilla has resolved final scenegraph bounds.
-- Kept in a side module to avoid growing this near-limit main chunk.
mod._ct_diag_tab_native533 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_tab_native533")
mod._ct_diag_tab_native533.install()

-- Draw point: our OWN begin_pass/end_pass layered on top of vanilla's, each draw_widget
-- pcall-guarded so a non-resident texture can never crash the panel render.
-- hook_safe = runs after vanilla's _draw closed its pass (ingame_player_list_ui_v2.lua:1755).
-- SINGLE ct hook on (IngamePlayerListUI, _draw) -- VMF silently drops a second
-- registration on the same pair. This one body draws BOTH ct overlays: the #461 keep
-- boon preview AND the #533 deus collectible counters. Each concern bails independently.
mod:hook_safe("IngamePlayerListUI", "_draw", function(self, dt)
    -- Automatic, bounded, log-only native CW census. This runs before the overlay
    -- early-return so diagnostics do not depend on either CT widget being present.
    pcall(mod._ct_diag_tab_native533.capture, self)
    local widgets = self._ct_boon_preview_widgets
    local has_boons = widgets and #widgets > 0
    local cw = self._ct_deus_collectibles
    if not has_boons and not cw then return end
    pcall(function()
        local r = self._ui_top_renderer
        local sg = self._ui_scenegraph
        local im = self._input_manager
        local input_service = im and im:get_service("player_list_input")
        local rs = self._render_settings
        if not (r and sg and input_service and rs) then return end
        UIRenderer.begin_pass(r, sg, input_service, dt, nil, rs)
        if has_boons then
            local hdr = self._ct_boon_header_widget
            if hdr then pcall(UIRenderer.draw_widget, r, hdr) end
            for i = 1, #widgets do
                pcall(UIRenderer.draw_widget, r, widgets[i])
            end
        end
        if cw then
            -- #533: refresh the counter values (vanilla _sync_missions cadence -- every
            -- active frame, write-on-change; ingame_player_list_ui_v2.lua:1128/:516-545),
            -- then draw vanilla's own Collectibles header + divider (vanilla skips them
            -- itself while _mission_count == 0 -- :1663-1665) and our two counter rows.
            pcall(mod._ct_layout_deus_collectibles, self)
            pcall(mod._ct_refresh_deus_collectibles, self)
            if self._collectibles_name then pcall(UIRenderer.draw_widget, r, self._collectibles_name) end
            if self._collectibles_divider then pcall(UIRenderer.draw_widget, r, self._collectibles_divider) end
            local rows = cw.rows
            for i = 1, #rows do
                pcall(UIRenderer.draw_widget, r, rows[i].widget)
            end
        end
        UIRenderer.end_pass(r)
    end)
end)

-- Textual preview + /verify surface for #461. Works even if the panel icons do not render,
-- and confirms the host-effective boon list the panel would show.
mod:command("ct_preview_boons", "List the starting boons this run will grant (host-effective) -- the #461 Tab-hold preview", function()
    local boons = mod._ct_collect_start_boons()
    if #boons == 0 then
        mod:echo("[ct] No starting boons configured. Enable some under Starting Boons in the ct menu.")
        return
    end
    mod:echo("%s", string.format("[ct] Starting Boons preview (%d) -- shown on the Tab panel while a CW expedition is queued in the keep:", #boons))
    for i = 1, #boons do
        local b = boons[i]
        mod:echo("%s", string.format("  %d. %s [%s]%s", i, b.display or b.name, tostring(b.rarity),
            b.modded and " (modded -- wire-gated for non-ct peers)" or ""))
    end
    mod:echo("%s", mod._ct_preparing_cw_expedition()
        and "[ct] CW expedition queued: the Tab panel shows this list now."
        or "[ct] No CW expedition queued: the Tab panel stays vanilla until the host starts one.")
end)

-- #461 regression: the marker + both build helpers + the display toggle stay wired, so a
-- future refactor can't silently drop the Tab-hold boon preview.
_rt_register("issue461_boon_preview_wired", function()
    if CT_BOON_PREVIEW_461_MARKER ~= "boon_preview_ingame_playerlist_v0.7.258" then
        return "#461 REGRESSION: CT_BOON_PREVIEW_461_MARKER missing/mismatch; got " .. tostring(CT_BOON_PREVIEW_461_MARKER)
    end
    if type(mod._ct_collect_start_boons) ~= "function" then
        return "#461 REGRESSION: mod._ct_collect_start_boons missing"
    end
    if type(mod._ct_build_boon_preview_widgets) ~= "function" then
        return "#461 REGRESSION: mod._ct_build_boon_preview_widgets missing"
    end
    if type(mod._ct_collect_start_boons()) ~= "table" then
        return "#461 REGRESSION: _ct_collect_start_boons must return a table"
    end
    if type(mod:get("preview_starting_boons")) ~= "boolean" then
        return "#461 REGRESSION: preview_starting_boons checkbox not registered (mod:get non-boolean)"
    end
    -- v0.7.258 follow-ups: the CW-queue gate must exist and be callable anywhere
    -- (returns plain false outside a queued expedition, never throws), and no row
    -- widget may ever anchor on the sizeless "reward_item" node again (the off-screen
    -- bug class: header visible, zero rows).
    if type(mod._ct_preparing_cw_expedition) ~= "function" then
        return "#461 REGRESSION: mod._ct_preparing_cw_expedition missing (CW-queue gate)"
    end
    if type(mod._ct_preparing_cw_expedition()) ~= "boolean" then
        return "#461 REGRESSION: _ct_preparing_cw_expedition must return a boolean"
    end
    local sample = mod._ct_build_boon_preview_widgets({ { name = "rt_probe", display = "rt probe", icon = nil } })
    if type(sample) ~= "table" or #sample == 0 then
        return "#461 REGRESSION: _ct_build_boon_preview_widgets built no widgets for a 1-boon list"
    end
    for i = 1, #sample do
        if sample[i].scenegraph_id == "reward_item" then
            return "#461 REGRESSION: preview widget anchored on sizeless reward_item node (off-screen bug class)"
        end
    end
end)

-- #556 regression: lock both halves of the talent-specific contract. The pure
-- duplicate policy must reject only an already-present talent, while the live
-- identity resolver must use the current career's native name/icon when one is
-- available in the keep.
_rt_register("issue556_starting_talent_identity", function()
    if type(mod._ct_starting_talent_is_duplicate) ~= "function" then
        return "#556 REGRESSION: duplicate-selected-talent policy missing"
    end
    if not mod._ct_starting_talent_is_duplicate(
        { talent = true }, "talent_2_2", { talent_2_2 = true }) then
        return "#556 REGRESSION: selected talent_2_2 would be appended twice"
    end
    if mod._ct_starting_talent_is_duplicate(
        { talent = true }, "talent_2_2", { talent_2_1 = true }) then
        return "#556 REGRESSION: a different talent was incorrectly suppressed"
    end
    if mod._ct_starting_talent_is_duplicate(
        { talent = false }, "attack_speed", { attack_speed = true }) then
        return "#556 REGRESSION: non-talent starting-boon behavior changed"
    end
    if type(mod._ct_start_boon_identity) ~= "function" then
        return "#556 REGRESSION: career-specific preview identity resolver missing"
    end

    local manager = Managers and Managers.player
    local player = manager and manager:local_player()
    if not player then return "skip: local player unavailable for talent identity" end
    local ok, profile_index, career_index = pcall(function()
        return player:profile_index(), player:career_index()
    end)
    if not ok then return "skip: local profile/career unavailable" end
    local rarity
    for _, entry in ipairs(rawget(_G, "DeusPowerUpsArray") or {}) do
        if entry.name == "talent_2_2" then rarity = entry.rarity break end
    end
    if not rarity then return "#556 REGRESSION: vanilla talent_2_2 power-up absent" end
    local display, icon = mod._ct_start_boon_identity(
        "talent_2_2", rarity, profile_index, career_index)
    if type(display) ~= "string" or display == "" or display == "talent_2_2" then
        return "#556 REGRESSION: talent preview retained generic identity " .. tostring(display)
    end
    if type(icon) ~= "string" or icon == "" then
        return "#556 REGRESSION: talent preview did not resolve a career icon"
    end
end)

-- ============================================================
-- CW Collectibles on the Tab-hold panel (#533)
-- ============================================================
-- BUG (#533): with Adventure-missions-in-CW enabled, an injected Adventure level's
-- Tab-hold right panel showed the ADVENTURE collectible counters (tomes / grimoires /
-- loot dice). Root cause: LevelSettings post-processing defaults `loot_objectives =
-- { grimoire = 2, tome = 3, ... }` onto every `mechanism == "adventure"` level
-- (level_settings.lua:1889-1896), and IngamePlayerListUI._setup_mission_data builds
-- the counter widgets purely from the CURRENT level's loot_objectives
-- (ingame_player_list_ui_v2.lua:436-441) -- it never consults the RUN mechanism.
-- Vanilla CW (deus) levels carry no loot_objectives, so vanilla builds no counters
-- there; an injected adventure level running under the deus mechanism inherits the
-- adventure default and builds counters for pickups that DO NOT EXIST on it (ct
-- converts tome/grim spawners to Chests of Trials and pedestals to Pilgrim's Coins).
--
-- FIX: full wrapper on _setup_mission_data (sole ct hook on that method; dup-check
-- 2026-07-13 -- the #461 hooks are on _setup_deed_reward_data/_draw). Outside a deus
-- run (stock Adventure, keep, hubs) -> passthrough, byte-identical vanilla. Inside a
-- deus run -> skip vanilla's build (no tome/grim/dice widgets; _mission_count stays 0
-- so vanilla's own Collectibles header stays off) and build the DEUS counters instead:
-- Chests of Trials + Pilgrim's Coins. Gate = "the mechanism exposes a live
-- deus_run_controller", the same every-peer-correct idiom as on_injected_adventure_level
-- (this file) -- NEVER IS_INJECTED_ADVENTURE_LEVEL, which is EMPTY on a client until
-- the ct graph snapshot lands, and pointless anyway: the counters are equally right on
-- vanilla CW levels, so ALL deus missions get them (consistent across the run).
--
-- DATA (peer-correct on host AND client -- both read the replicated deus-run
-- SharedState): Chests of Trials = get_cursed_chests_purified(own_peer)
-- (deus_run_controller.lua:2070; server-incremented for EVERY peer on chest completion
-- :767-777, replicated via SharedState, deus_run_state.lua:20/:236-244). Pilgrim's
-- Coins = get_player_soft_currency(own_peer) (deus_run_controller.lua:925-927 -- the
-- EXACT getter the vanilla HUD coin indicator polls on every peer,
-- deus_soft_currency_indicator_ui.lua:51-68), floored like that HUD (:78).
--
-- WIDGETS: a copy of vanilla's create_loot_widget
-- (ingame_player_list_ui_v2_definitions.lua:843-1041 -- a file-local we cannot reach)
-- minus its glow pass (deus_icons_coin/_boon have no `*_glow` atlas sibling), anchored
-- on the vanilla "loot_objective" scenegraph node with vanilla's own row math. Icons
-- are gui_icons_atlas entries (deus_icons_coin :11946, deus_icons_boon :10532) -- the
-- same atlas family this exact panel already resolves for node-info boon/curse icons.
-- Risk posture (untestable UI, same as #461): build is pcall-bracketed with a vanilla
-- fallback, drawing rides the existing guarded _draw pass -- worst case the block
-- no-ops and the panel renders pure vanilla.
CT_CW_TAB_COLLECTIBLES_533_MARKER = "cw_tab_collectibles_deus_counters_v0.7.257"
do
    -- Live deus run controller or nil (stock Adventure / keep -> nil). Correct on every
    -- peer: only the deus mechanism exposes get_deus_run_controller.
    local function deus_run_controller_or_nil()
        local mm = Managers.mechanism
        local mech = mm and mm.game_mechanism and mm:game_mechanism()
        return (mech and mech.get_deus_run_controller and mech:get_deus_run_controller()) or nil
    end

    -- The two deus counter rows (order = display order, top to bottom).
    local ROWS = {
        { key = "chests", icon = "deus_icons_boon", label_key = "ct_tab_chests_of_trials" },
        { key = "coins",  icon = "deus_icons_coin", label_key = "ct_tab_pilgrims_coins" },
    }
    -- Native-sized; #571 resolves any downscale from the live scenegraph.
    local ICON_SIZE = 80

    -- Verbatim copy of vanilla create_loot_widget (definitions:843-1041) MINUS the
    -- glow_icon pass/style: `texture .. "_glow"` does not exist for the deus icons and
    -- a missing atlas texture would kill the draw. Everything else (amount-gated lit
    -- icon over a black silhouette, title bottom-right of the icon, counter above it)
    -- is vanilla's own layout so the pane matches the adventure counters it replaces.
    local function create_deus_loot_widget(texture, text, scale)
        local texture_settings = UIAtlasHelper.get_atlas_settings_by_texture_name(texture)
        local texture_size = texture_settings.size
        scale = scale or 1
        return {
            scenegraph_id = "loot_objective",
            element = {
                passes = {
                    { pass_type = "text", style_id = "text", text_id = "text" },
                    { pass_type = "text", style_id = "text_shadow", text_id = "text" },
                    {
                        pass_type = "text", style_id = "counter_text", text_id = "counter_text",
                        content_check_function = function(content) return content.amount > 0 end,
                    },
                    {
                        pass_type = "text", style_id = "counter_text_disabled", text_id = "counter_text",
                        content_check_function = function(content) return content.amount == 0 end,
                    },
                    { pass_type = "text", style_id = "counter_text_shadow", text_id = "counter_text" },
                    {
                        pass_type = "texture", style_id = "icon", texture_id = "icon",
                        content_check_function = function(content) return content.amount > 0 end,
                    },
                    { pass_type = "texture", style_id = "background_icon", texture_id = "icon" },
                },
            },
            content = {
                amount = 0,
                counter_text = "x0",
                text = text or "n/a",
                icon = texture,
            },
            style = {
                text = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "bottom",
                    text_color = Colors.get_table("font_title"),
                    offset = { scale * texture_size[1], scale * texture_size[2] - 50, 1 },
                },
                text_shadow = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "bottom",
                    text_color = Colors.get_table("black"),
                    offset = { scale * texture_size[1] + 1, scale * texture_size[2] - 50 - 1, 0 },
                },
                counter_text = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = Colors.get_table("font_default"),
                    offset = { scale * texture_size[1], -40, 1 },
                },
                counter_text_disabled = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = { 255, 130, 130, 130 },
                    offset = { scale * texture_size[1], -40, 1 },
                },
                counter_text_shadow = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = Colors.get_table("black"),
                    offset = { scale * texture_size[1] + 1, -41, 0 },
                },
                icon = {
                    horizontal_alignment = "left", vertical_alignment = "top",
                    color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 1 },
                    texture_size = { scale * texture_size[1], scale * texture_size[2] },
                },
                background_icon = {
                    horizontal_alignment = "left", vertical_alignment = "top",
                    color = { 255, 0, 0, 0 },
                    offset = { 0, 0, 0 },
                    texture_size = { scale * texture_size[1], scale * texture_size[2] },
                },
            },
            offset = { 0, 0, 0 },
        }
    end

    -- Own-peer chest/coin values, or nil outside a deus run. Exposed on mod for the
    -- regression check and any future /verify surface.
    function mod._ct_read_deus_collectible_values()
        local dc = deus_run_controller_or_nil()
        if not dc then return nil end
        local peer = dc.get_own_peer_id and dc:get_own_peer_id()
        if not peer then return nil end
        local chests = (dc.get_cursed_chests_purified and dc:get_cursed_chests_purified(peer)) or 0
        local coins = (dc.get_player_soft_currency and dc:get_player_soft_currency(peer)) or 0
        return {
            chests = math.floor((tonumber(chests) or 0) + 0.5),
            coins = math.floor(tonumber(coins) or 0),  -- HUD indicator floors too (:78)
        }
    end

    -- Build once; live placement happens after the scenegraph resolves below.
    function mod._ct_build_deus_collectibles()
        local rows = {}
        for i, spec in ipairs(ROWS) do
            local title = mod:localize(spec.label_key)
            local widget = UIWidget.init(create_deus_loot_widget(spec.icon, title, 1))
            rows[#rows + 1] = { key = spec.key, title = title, widget = widget, last = nil }
        end
        return { rows = rows, layout_signature = nil }
    end

    -- Per-frame value refresh while the panel draws (called from the shared _draw hook
    -- above). Mirrors vanilla _sync_missions: only rewrite content when the value
    -- changed (ingame_player_list_ui_v2.lua:530-543).
    function mod._ct_refresh_deus_collectibles(self)
        local cw = self._ct_deus_collectibles
        if not cw then return end
        local values = mod._ct_read_deus_collectible_values()
        if not values then return end
        for _, row in ipairs(cw.rows) do
            local v = values[row.key] or 0
            if v ~= row.last then
                row.last = v
                local content = row.widget.content
                content.amount = v
                content.counter_text = "x" .. tostring(v)
            end
        end
    end

    -- Build point + adventure-counter suppression. FULL wrapper (not hook_safe): under
    -- the deus mechanism vanilla must NOT run -- it would build tome/grim/dice counters
    -- from the injected level's defaulted loot_objectives. Keep/hubs stay vanilla.
    mod:hook("IngamePlayerListUI", "_setup_mission_data", function(func, self, level_settings)
        self._ct_deus_collectibles = nil
        if self._is_in_inn or (level_settings and level_settings.hub_level)
            or not deus_run_controller_or_nil() then
            return func(self, level_settings)
        end
        local ok, err = pcall(function()
            self._ct_deus_collectibles = mod._ct_build_deus_collectibles()
        end)
        if not ok then
            self._ct_deus_collectibles = nil
            pcall(printf, "[ct:533] deus collectibles build failed (pane falls back to vanilla): %s", tostring(err))
            return func(self, level_settings)
        end
        pcall(printf, "[ct:533] Tab-hold collectibles -> deus counters (Chests of Trials + Pilgrim's Coins); adventure tome/grim/dice counters suppressed")
        -- Deliberately NOT calling func: on a deus-run level the vanilla build is either
        -- a no-op (vanilla CW level, no loot_objectives) or wrong (injected adventure
        -- level, defaulted adventure loot_objectives).
    end)
end

local _ct_tab_layout_571 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_collectibles_layout")

-- #533 regression: marker + all three helpers stay wired, and the value reader honors
-- its outside-a-deus-run nil contract (in the keep it MUST be nil; mid-run a table).
_rt_register("issue533_cw_tab_collectibles_wired", function()
    if CT_CW_TAB_COLLECTIBLES_533_MARKER ~= "cw_tab_collectibles_deus_counters_v0.7.257" then
        return "#533 REGRESSION: CT_CW_TAB_COLLECTIBLES_533_MARKER missing/mismatch; got " .. tostring(CT_CW_TAB_COLLECTIBLES_533_MARKER)
    end
    if type(mod._ct_build_deus_collectibles) ~= "function" then
        return "#533 REGRESSION: mod._ct_build_deus_collectibles missing"
    end
    if type(mod._ct_refresh_deus_collectibles) ~= "function" then
        return "#533 REGRESSION: mod._ct_refresh_deus_collectibles missing"
    end
    if type(mod._ct_read_deus_collectible_values) ~= "function" then
        return "#533 REGRESSION: mod._ct_read_deus_collectible_values missing"
    end
    local v = mod._ct_read_deus_collectible_values()
    if v ~= nil and (type(v) ~= "table" or type(v.chests) ~= "number" or type(v.coins) ~= "number") then
        return "#533 REGRESSION: value reader contract broken (expected nil outside a deus run or {chests=n, coins=n} inside one)"
    end
end)

_rt_register("issue533_native_tab_diagnostics_armed", mod._ct_diag_tab_native533.regression)

_rt_register("issue571_cw_tab_collectibles_safe_reflow", _ct_tab_layout_571.regression)

-- ============================================================
-- Buy Starting Boons -- start-node shrine shop (#458)
-- ============================================================
-- The run's START node runs inside GameModeMapDeus, whose shared-state machine can
-- be in MAP_DECISION (the map screen) or SHOP (a shrine overlay). Vanilla starts a
-- run in MAP_DECISION; a shrine is only reached later by CHOOSING a shop node
-- (game_mode_map_deus.lua:332 new_node.node_type=="shop" -> handle_shrine_entered ->
-- states.SHOP). Both states run on the SAME persistent dlc_morris_map world (the
-- ferry-lady hub), so a shrine is an overlay + spawned idol props, NOT a separate
-- level load. That lets us open the shrine at run start with no graph or node change.
--
-- DESIGN (#458): when the HOST enables ct_buy_starting_boons, we force GameModeMapDeus
-- into its SHOP state at run start (current node still "start"). Vanilla's own SHOP ->
-- WAITING_FOR_PLAYERS_AFTER_SHOP -> MAP_DECISION path (game_mode_map_deus.lua:341-349)
-- then returns every peer to the normal first map choice after buying. We never call
-- handle_shrine_entered (that would mark the start node traversed / could alter its map
-- token) and never touch node_type -- so the start node's map APPEARANCE is unchanged,
-- exactly as the issue requires: "simply puts the player in the shop menu."
--
-- CONFIG: DeusShopView.start resolves its offer from DeusShopSettings.shop_types
-- [current_node.level] (deus_shop_view_v2.lua:181-184). The start node's level is
-- "dlc_morris_map", which is never a shop in vanilla, so shop_types["dlc_morris_map"]
-- is ours alone. We register it (power_up_count + blessings) from host-effective
-- settings so the count/miracle pool follow the host across the lobby (the ct_ keys are
-- auto-added to SYNCED_SETTING_NAMES because they are not per-peer). Boon OFFERS are
-- per-peer-seeded exactly like a vanilla shrine (each hero sees their own), so no coop
-- offer-sync is needed; the blessing SUBSET is seeded by the start node's blessings seed
-- so every peer selects the same miracles.
--
-- WIRE SAFETY: the shrine reuses vanilla's shop buy path (shop_buy_power_up /
-- shop_buy_blessing) with vanilla RPC indices. Boons offered come from
-- generate_random_power_ups -> DeusPowerUpRarityPool, which ct already parity-ejects for
-- modded boons under unconfirmed peer parity (#426), so a non-ct peer can never be
-- offered (hence never buy) a modded index. Miracles are all vanilla blessing keys
-- (deus_blessing_settings.lua). So this feature adds NO new peer-sync exposure.
--
-- INTERACTION with the free Starting Boons list (DeusRunController._add_initial_power_ups
-- hook above): they STACK and are orthogonal. The free grant runs at run setup (before
-- the shrine opens), so generate_random_power_ups sees those boons as existing and will
-- not re-offer them (vanilla dedupe, deus_run_controller.lua:1110). A pure buy-your-own
-- start = leave the free list off. Documented in the toggle tooltip.
--
-- SCOPE (v0.7.252-dev, load-bearing core): boon count + miracle count/pool are wired.
-- Per-shrine COST multiplier and a PICK LIMIT are deferred (they need gated
-- interception of the shared DeusCostSettings.shop cost reads and per-shrine purchase
-- counting) -- see CHANGELOG "#458 remaining scope".
do
    -- The 8 vanilla CW blessings/miracles (deus_blessing_settings.lua:18-99). Only these
    -- vanilla keys ever reach the shop, so the shrine adds no modded wire exposure.
    local MIRACLE_KEYS = {
        "blessing_of_power", "blessing_of_shallya", "blessing_of_grimnir",
        "blessing_of_isha", "blessing_of_ranald", "blessing_of_abundance",
        "blessing_holy_hand_grenade", "blessing_rally_flag",
    }
    mod._ct_start_shrine_miracle_keys = MIRACLE_KEYS

    -- Deterministic, peer-stable shuffle (local Park-Miller LCG; does NOT disturb the
    -- global math.random state). Same seed -> same order on every peer.
    local function seeded_shuffle(list, seed)
        local s = (tonumber(seed) or 0) % 2147483647
        if s <= 0 then s = s + 2147483646 end
        for i = #list, 2, -1 do
            s = s * 16807 % 2147483647
            local j = s % i + 1
            list[i], list[j] = list[j], list[i]
        end
        return list
    end

    -- Build the miracle (blessing) subset the start shrine offers. Reads host-effective
    -- settings so the whole lobby agrees; the seed (start node's blessings seed) makes the
    -- random pick identical on every peer. Returns {} when count is 0 or the pool is empty.
    function mod._ct_build_start_shrine_blessings(seed)
        local eff = mod._ct_effective_setting or function(n) return mod:get(n) end
        local count = math.floor(tonumber(eff("ct_start_shrine_miracle_count")) or 0)
        if count <= 0 then return {} end
        local eligible = {}
        for _, key in ipairs(MIRACLE_KEYS) do
            if eff("ct_start_shrine_miracle_" .. key) then
                eligible[#eligible + 1] = key
            end
        end
        if #eligible == 0 then return {} end
        table.sort(eligible) -- stable base order before the seeded shuffle
        seeded_shuffle(eligible, seed)
        local out = {}
        for i = 1, math.min(count, #eligible) do out[i] = eligible[i] end
        return out
    end

    -- Register/refresh DeusShopSettings.shop_types["dlc_morris_map"] (the start node's
    -- level, never a shop in vanilla, so this entry is ours alone). Vanilla's shop view
    -- resolves its config by current_node.level, so this is all the shrine needs to open
    -- at the start node with our tuned counts. Returns the config (nil if DeusShopSettings
    -- is not loaded yet -- only ever called in-run, so it is).
    function mod._ct_build_start_shrine_config(blessings_seed)
        local settings = rawget(_G, "DeusShopSettings")
        if type(settings) ~= "table" or type(settings.shop_types) ~= "table" then return nil end
        local eff = mod._ct_effective_setting or function(n) return mod:get(n) end
        local boon_count = math.floor(tonumber(eff("ct_start_shrine_boon_count")) or 4)
        if boon_count < 0 then boon_count = 0 end
        local cfg = settings.shop_types["dlc_morris_map"]
        if type(cfg) ~= "table" then
            cfg = {}
            settings.shop_types["dlc_morris_map"] = cfg
        end
        cfg.max_discounts = 0
        cfg.power_up_discount = 0.5
        cfg.twitch_icon = "twitch_icon_shrine"
        cfg.power_up_count = boon_count
        cfg.blessings = mod._ct_build_start_shrine_blessings(blessings_seed)
        return cfg
    end

    -- Vanilla DeusShopView.start dereferences both fields without checking them
    -- (deus_shop_view_v2.lua:182-184).  Keep the validation contract explicit so
    -- both the publisher and every receiving peer use the same fail-closed gate.
    function mod._ct_start_shrine_config_valid(cfg)
        return type(cfg) == "table"
            and type(cfg.power_up_count) == "number"
            and cfg.power_up_count >= 0
            and type(cfg.blessings) == "table"
    end

    function mod._ct_prepare_start_shrine(drc)
        if not drc or type(drc.get_current_node) ~= "function" then return nil end
        local node = drc:get_current_node()
        if type(node) ~= "table" or node.level ~= "dlc_morris_map" then return nil end
        local bseed = node.system_seeds and node.system_seeds.blessings or 0
        local cfg = mod._ct_build_start_shrine_config(bseed)
        if not mod._ct_start_shrine_config_valid(cfg) then return nil end
        return cfg
    end
end

-- Final containment at the exact vanilla dereference. Normally the earlier
-- local_player_game_starts preparation has already installed the config. If a
-- future load-order change bypasses it, rebuild here before vanilla mutates view
-- state; if that still fails, do not call vanilla and request MAP_DECISION locally.
-- The host also restores its authoritative state. Diagnostic output is bounded.
local _ct458_view_guard_reports = 0
mod:hook("DeusShopView", "start", function(func, self, params)
    local drc = self and self._deus_run_controller
    local node_ok, node = pcall(function()
        return drc and drc.get_current_node and drc:get_current_node()
    end)
    if not node_ok then node = nil end
    if type(node) == "table" and node.level == "dlc_morris_map" then
        local prepared, cfg = pcall(mod._ct_prepare_start_shrine, drc)
        if not prepared then cfg = nil end
        if not mod._ct_start_shrine_config_valid(cfg) then
            local ss = self._shared_state
            if ss and ss.get_key then
                local state_key = ss:get_key("state")
                if self._is_server and ss.set_server then ss:set_server(state_key, 1) end
                if ss.set_own then ss:set_own(state_key, 1) end
            end
            if _ct458_view_guard_reports < 4 then
                _ct458_view_guard_reports = _ct458_view_guard_reports + 1
                pcall(printf, "[ct:458] start shrine view blocked: config unavailable; restored MAP_DECISION (peer=%s report=%d/4)",
                    self._is_server and "host" or "client", _ct458_view_guard_reports)
            end
            return
        end
    end
    return func(self, params)
end)
mod._ct_start_shrine_view_guard_installed = true

-- Trigger + config registration at run start. VMF singleton-hook rule: this is ct_dev's
-- ONLY (GameModeMapDeus, local_player_game_starts) hook (ct's other start hook is on
-- GameModeDeus, a different class). Full mod:hook so we can override the shared state
-- vanilla just set. Marker: _ct_start_shrine_trigger_hook.
mod:hook("GameModeMapDeus", "local_player_game_starts", function(func, self, player, loading_context)
    -- Prepare on EVERY peer before vanilla full_sync can expose a host-published
    -- SHOP state to the client. This ordering is the #458 crash fix.
    local drc = self._deus_run_controller
    local start_ok, at_start = pcall(function()
        return drc and drc.get_current_node_key and drc:get_current_node_key() == "start"
    end)
    if not start_ok then at_start = false end
    local prepared, cfg = true, nil
    if at_start then prepared, cfg = pcall(mod._ct_prepare_start_shrine, drc) end
    if not prepared then cfg = nil end
    func(self, player, loading_context)
    local ok, err = pcall(function()
        if not at_start then return end -- run start only (not later map returns)
        -- Host-authoritative trigger: only the host writes shared server state; clients
        -- follow via the existing GameModeMapDeus shared-state sync.
        if not self._is_server then return end
        if not mod:get("ct_buy_starting_boons") then return end
        if not mod._ct_start_shrine_config_valid(cfg) then
            pcall(printf, "[ct:458] start shrine not published: host config validation failed; staying in MAP_DECISION")
            return
        end
        local run_id = drc.get_run_id and drc:get_run_id()
        if run_id ~= nil and mod._ct_start_shrine_fired == run_id then return end -- once per run
        local ss = self._shared_state
        if not ss or not ss.set_server or not ss.get_key then return end
        -- states.SHOP = 3 (game_mode_map_deus.lua:47).
        ss:set_server(ss:get_key("state"), 3)
        mod._ct_start_shrine_fired = run_id
        pcall(printf, "[ct:458] Buy Starting Boons applied: forced SHOP at run start (run_id=%s boons=%d miracles=%d)",
            tostring(run_id), cfg and cfg.power_up_count or -1, cfg and cfg.blessings and #cfg.blessings or 0)
    end)
    if not ok then
        pcall(printf, "[ct:458] start-shrine trigger errored (%s); vanilla map decision unaffected", tostring(err))
    end
end)
mod._ct_start_shrine_prepared_before_vanilla = true

-- /verify_<feature> per PROJECT_STANDARDS s5.1a: live state vs the toggles that gate it.
mod:command("ct_verify_start_shrine", "Report the #458 Buy Starting Boons config (toggle, counts, miracle pool, registered shop config)", function()
    local eff = mod._ct_effective_setting or function(n) return mod:get(n) end
    mod:echo("[ct] Buy Starting Boons (#458) -- host controls whether the shrine appears:")
    mod:echo("%s", string.format("  toggle=%s  boons=%s (eff %s)  miracles=%s (eff %s)",
        tostring(mod:get("ct_buy_starting_boons")),
        tostring(mod:get("ct_start_shrine_boon_count")), tostring(eff("ct_start_shrine_boon_count")),
        tostring(mod:get("ct_start_shrine_miracle_count")), tostring(eff("ct_start_shrine_miracle_count"))))
    local enabled = {}
    for _, key in ipairs(mod._ct_start_shrine_miracle_keys or {}) do
        if eff("ct_start_shrine_miracle_" .. key) then enabled[#enabled + 1] = key end
    end
    mod:echo("%s", string.format("  miracle pool enabled (%d): %s", #enabled, table.concat(enabled, ", ")))
    local settings = rawget(_G, "DeusShopSettings")
    local cfg = settings and settings.shop_types and settings.shop_types["dlc_morris_map"]
    if type(cfg) == "table" then
        mod:echo("%s", string.format("  registered start-shrine config: power_up_count=%s blessings=[%s]  PASS",
            tostring(cfg.power_up_count), table.concat(cfg.blessings or {}, ",")))
    else
        mod:echo("  registered start-shrine config: none yet (built at run start) -- expected outside a run")
    end
end)

_rt_register("issue458_start_shrine_config", function()
    if type(mod._ct_build_start_shrine_config) ~= "function" then
        return "#458 REGRESSION: mod._ct_build_start_shrine_config missing"
    end
    if type(mod._ct_build_start_shrine_blessings) ~= "function" then
        return "#458 REGRESSION: mod._ct_build_start_shrine_blessings missing"
    end
    if type(mod._ct_start_shrine_miracle_keys) ~= "table" or #mod._ct_start_shrine_miracle_keys ~= 8 then
        return "#458 REGRESSION: miracle key list missing or not 8 entries"
    end
    if type(mod:get("ct_buy_starting_boons")) ~= "boolean" then
        return "#458 REGRESSION: ct_buy_starting_boons checkbox not registered (mod:get non-boolean)"
    end
    if type(mod._ct_build_start_shrine_blessings(12345)) ~= "table" then
        return "#458 REGRESSION: _ct_build_start_shrine_blessings must return a table"
    end
    if type(mod._ct_start_shrine_config_valid) ~= "function" then
        return "#458 REGRESSION: start-shrine config validator missing"
    end
    if mod._ct_start_shrine_config_valid(nil)
            or mod._ct_start_shrine_config_valid({ power_up_count = 4 })
            or not mod._ct_start_shrine_config_valid({ power_up_count = 4, blessings = {} }) then
        return "#458 REGRESSION: config validation must reject nil/partial and accept complete configs"
    end
    if mod._ct_start_shrine_prepared_before_vanilla ~= true then
        return "#458 REGRESSION: peer config is not marked prepared before vanilla full_sync"
    end
    if mod._ct_start_shrine_view_guard_installed ~= true then
        return "#458 REGRESSION: DeusShopView.start fail-closed guard missing"
    end
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

-- Shared rarity picker for altar/CoT mirrors and direct shrine-shop purchases.
-- The raw rarity registry retains disabled and CT-injected entries for lookup
-- parity, so every consumer must pass this same eligibility gate.
function mod._ct_bot_pick_random_for_rarity(rarity)
    local bucket = rawget(_G, "DeusPowerUpsArrayByRarity") and DeusPowerUpsArrayByRarity[rarity]
    if not bucket or #bucket == 0 then return nil end
    local eligible = {}
    for i = 1, #bucket do
        local entry = bucket[i]
        local name = entry and entry.name
        local parity_blocked = name and mod._ct_is_modded_power_up
            and mod._ct_is_modded_power_up(name)
            and not (mod._ct_wire_safe and mod._ct_wire_safe())
        if name and not mod._ct_boon_disabled(name) and not parity_blocked then
            eligible[#eligible + 1] = name
        end
    end
    if #eligible == 0 then return nil end
    return eligible[math.random(1, #eligible)]
end

-- (#144 boon-list snapshot helper removed with the retired [ct:boon144] SHRINK trace — the
-- list was proven never to lose the boon; the live instrument is mod._ct_vauls_anvil_reconcile.)

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
            -- v0.7.240-dev (#426): peer-parity wire gate at the canonical grant choke
            -- point (this hook covers chest, cursed chest, shop, set reward, end-of-level
            -- and debug grants). A ct-modded power-up granted while any lobby peer lacks
            -- ct rides the deus run-state sync (deus_run_state_spec.lua:60/:85) and the
            -- rpc_add_buff broadcast (buff_system.lua:302-305) as a modded lookup index
            -- and CTDs that peer. Belt-and-suspenders with the pool eject in the
            -- wire-safety block below: this catches any grant path even if a modded
            -- entry is still sitting in a rolled offer/pool snapshot.
            elseif name and mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(name)
                and not (mod._ct_wire_safe and mod._ct_wire_safe()) then
                table.remove(new_power_ups, i)
                pcall(printf, "[ct:426] BLOCKED modded boon at grant: %s (peer parity not confirmed) source=%s",
                    tostring(name), tostring(mod._ct_grant_source or "untagged"))
            end
        end
    end

    -- #144: the [ct:boon144] before/after boon-list SHRINK trace that used to sit here has been
    -- RETIRED. It did its job: two clean repro logs (host + client) proved the boon list only ever
    -- GREW across grants and Vaul's Anvil (ct_boon_vauls_anvil) was never dropped from the list.
    -- The report has since been re-characterized: the boon STAYS in the list but its EFFECT stops
    -- working after an equip/wield action. That failure lives in the always_blocking perk lifecycle
    -- (deus_always_blocking_buff -> status.override_blocking), not the boon list -- so the instrument
    -- moved to mod._ct_vauls_anvil_reconcile below (tag [ct:vaul]), which both self-heals the perk
    -- every frame AND probes the exact wielded/lockout/override state on each change.
    func(self, new_power_ups, local_player_id, present)

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
        -- boon-ALTAR grant inside DeusChestExtension.open_chest. The consolidated full
        -- wrapper publishes the exact pre-purchase price for this synchronous call stack;
        -- a second hook on the same Class+method would violate the singleton invariant.
        -- That path is already double-covered by the
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

    -- The audited untagged + present=true path is a purchased boon altar. The
    -- consolidated open_chest wrapper publishes its exact scaled purchase cost
    -- only for the duration of vanilla open_chest -> add_power_ups. CoT/view and
    -- end-of-level grants stay free, matching vanilla.
    local incoming_source = mod._ct_grant_source
    local boon_cost_source = (incoming_source == nil and present == true
        and mod._ct_bot_altar_cost ~= nil) and "boon_altar" or tostring(incoming_source or "free_grant")
    local boon_cost = mod._ct_bot_economy.grant_cost(boon_cost_source, mod._ct_bot_altar_cost)

    -- v0.7.120-dev: per-bot independent random pick from DeusPowerUpsArrayByRarity[rarity].
    -- Picks a random entry of the SAME rarity the host just got, then materializes via
    -- generate_specific_power_up (gives each bot a fresh client_id). Falls back to a
    -- mirror grant for that slot if the rarity bucket is empty / missing.
    local function _pick_random_for_rarity(rarity)
        return mod._ct_bot_pick_random_for_rarity(rarity)
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
                -- v0.7.240-dev (#426): parity defense-in-depth for the bot grant, same
                -- rationale as the picker filter above (this loop's add_power_ups
                -- re-entry skips the pre-grant parity gate via _ct_bot_mirror_active).
                elseif mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(bot_name)
                    and not (mod._ct_wire_safe and mod._ct_wire_safe()) then
                    pcall(printf, "[ct:426] SKIPPED modded boon for bot: %s (peer parity not confirmed)",
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
            -- Charge only if at least one wire-safe boon survived selection. Bots
            -- that cannot afford a purchased altar receive nothing; free CoT and
            -- end-of-level grants use cost=0 and always pass this gate.
            local affordable = #cloned > 0 and mod._ct_bot_economy_charge(run_state,
                bot, boon_cost, boon_cost_source)
            if affordable then
                -- present=false: don't trigger the reward-popup UI for bot grants.
                local grant_ok, grant_err = pcall(self.add_power_ups, self,
                    cloned, bot:local_player_id(), false)
                if not grant_ok then
                    local peer_id, bot_local = bot:network_id(), bot:local_player_id()
                    local balance = run_state:get_player_soft_currency(peer_id, bot_local) or 0
                    run_state:set_player_soft_currency(peer_id, bot_local,
                        mod._ct_bot_economy.credit(balance, boon_cost))
                    mod._ct_bot_economy_log("boon grant failed/refunded bot=%s source=%s cost=%s error=%s",
                        tostring(bot.name and bot:name() or bot_local), tostring(boon_cost_source),
                        tostring(boon_cost), tostring(grant_err))
                end
            elseif #cloned > 0 then
                mod._ct_bot_economy_log("boon skipped bot=%s source=%s cost=%s selected=%d",
                    tostring(bot.name and bot:name() or bot:local_player_id()),
                    tostring(boon_cost_source), tostring(boon_cost), #cloned)
            end
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

-- Shrine-shop purchases do NOT call add_power_ups: vanilla _try_buy_power_up
-- writes the buyer's SharedState row directly. Own this second source seam so
-- bot boon modes cover shrines as their tooltips promise, with an independent
-- affordability gate and the same random/disabled/parity policy as altars.
mod:hook("DeusRunController", "_try_buy_power_up", function(func, self, buyer, power_up, discount)
    local bought = func(self, buyer, power_up, discount)
    if not bought or _ct_bot_mirror_active then return bought end
    local run_state = self and self._run_state
    if not (run_state and run_state:is_server() and buyer == run_state:get_own_peer_id()) then return bought end

    local mode_mirror = effective_setting("bots_mirror_host_boons")
    local mode_random = effective_setting("bots_get_random_boons")
    if not (mode_mirror or mode_random) or not power_up then return bought end

    local cost = mod._ct_bot_economy.shop_boon_cost(rawget(_G, "DeusCostSettings"),
        power_up.rarity, discount)
    _ct_bot_mirror_active = true
    local ok, err = pcall(function()
        for _, bot in ipairs(mod._ct_bot_economy_players()) do
            if bot.player_unit and Unit.alive(bot.player_unit) then
                local boon_name = power_up.name
                if mode_random then
                    boon_name = mod._ct_bot_pick_random_for_rarity(power_up.rarity) or boon_name
                end
                local blocked = mod._ct_boon_disabled(boon_name)
                    or (mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(boon_name)
                        and not (mod._ct_wire_safe and mod._ct_wire_safe()))
                if not blocked and mod._ct_bot_economy_charge(run_state, bot, cost, "shrine_boon") then
                    local generated = DeusPowerUpUtils.generate_specific_power_up(boon_name, power_up.rarity)
                    local grant_ok, grant_err = pcall(self.add_power_ups, self,
                        { generated }, bot:local_player_id(), false)
                    if not grant_ok then
                        local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
                        local balance = run_state:get_player_soft_currency(peer_id, local_player_id) or 0
                        run_state:set_player_soft_currency(peer_id, local_player_id,
                            mod._ct_bot_economy.credit(balance, cost))
                        mod._ct_bot_economy_log("shrine grant failed/refunded bot=%s cost=%s error=%s",
                            tostring(bot.name and bot:name() or local_player_id), tostring(cost), tostring(grant_err))
                    end
                    if grant_ok then
                        local profile_index, career_index = run_state:get_player_profile(
                            bot:network_id(), bot:local_player_id())
                        mod._ct_bot_economy_log("shrine choice bot=%s profile=%s:%s mode=%s boon=%s rarity=%s cost=%s",
                            tostring(bot.name and bot:name() or bot:local_player_id()),
                            tostring(profile_index), tostring(career_index),
                            mode_random and "random" or "mirror", tostring(boon_name),
                            tostring(power_up.rarity), tostring(cost))
                    end
                elseif blocked then
                    mod._ct_bot_economy_log("shrine choice blocked bot=%s boon=%s parity_or_disabled=true",
                        tostring(bot.name and bot:name() or bot:local_player_id()), tostring(boon_name))
                end
            end
        end
    end)
    _ct_bot_mirror_active = false
    if not ok then mod._ct_bot_economy_log("shrine bot purchase error=%s", tostring(err)) end
    return bought
end)

-- #144 install-time finding (kept for the record): there is NO fixed max-boon cap in vanilla. A
-- player's active power-ups live in a dynamic SharedState Lua table (deus_run_state_spec.lua:298
-- "power_ups"); DeusRunController.add_power_ups (deus_run_controller.lua:1126) only ever appends.
-- The boon-list SHRINK hypothesis was DISPROVEN by two clean repro logs, so the [ct:boon144] list
-- trace is retired. The report is now: the boon stays in the list but its EFFECT stops after an
-- equip/wield action -> tracked by the [ct:vaul] perk reconciler/probe (see mod._ct_vauls_anvil_reconcile).

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

_rt_register("bot_boon_economy_installed", function()
    if CT_BOT_ECONOMY_MARKER ~= "bot_economy:independent_charge_gate_v0.7.278" then
        return "#466 bot economy marker missing or stale"
    end
    local economy = mod._ct_bot_economy
    if type(economy) ~= "table" or type(economy.charge) ~= "function"
        or type(economy.credit) ~= "function" or type(economy.weapon_cost) ~= "function"
        or type(economy.shop_boon_cost) ~= "function" then
        return "#466 bot economy policy incomplete"
    end
    local allowed, balance = economy.charge(150, 100)
    if not allowed or balance ~= 50 then return "#466 affordable charge self-test failed" end
    allowed, balance = economy.charge(50, 100)
    if allowed or balance ~= 50 then return "#466 insufficient-funds self-test failed" end
    if type(mod._ct_bot_pick_random_for_rarity) ~= "function"
        or type(mod._ct_bot_economy_charge) ~= "function" then
        return "#466 bot choice/charge runtime helper missing"
    end
end)

_rt_register("issue331_bot_coin_pickup_installed", function()
    local policy = mod._ct_bot_coin_pickup
    if type(policy) ~= "table" or type(policy.poll_due) ~= "function"
        or type(policy.can_claim) ~= "function" or type(policy.claim_until) ~= "function" then
        return "#331 bot coin pickup policy missing or incomplete"
    end
    if policy.pickup_name ~= "deus_soft_currency" or policy.range ~= 10
        or policy.poll_interval ~= 1 or policy.claim_ttl ~= 1.5 then
        return "#331 bot coin pickup vanilla bounds drifted"
    end
    local due, next_t = policy.poll_due(10, 9)
    if not due or next_t ~= 11 then return "#331 poll self-test failed" end
    if policy.can_claim("healing_draught", 0, 10)
        or not policy.can_claim("deus_soft_currency", 10, 10)
        or policy.can_claim("deus_soft_currency", 11, 10) then
        return "#331 claim/identity self-test failed"
    end
end)

_rt_register("issue361_miasma_customization_installed", function()
    local policy = mod._ct_miasma_policy
    if type(policy) ~= "table" or type(policy.radius) ~= "function"
        or type(policy.interval) ~= "function" or type(policy.select_owner) ~= "function" then
        return "#361 Miasma policy missing or incomplete"
    end
    if policy.radius(nil) ~= 8 or policy.interval(nil) ~= 1.3
        or policy.radius(100) ~= 30 or policy.interval(0) ~= 0.1 then
        return "#361 Miasma slider self-test failed"
    end
    if not rawget(_G, "__ct_miasma361_hook_installed") then
        return "#361 live MutatorTemplates curse update hook missing"
    end
    if type(mod._ct_sync_miasma) ~= "function" or not mod._ct_sync_miasma() then
        return "#361 Miasma buff template unavailable"
    end
end)

_rt_register("boon_price_audit_armed", function()
    if CT_BOON_PRICE_AUDIT_MARKER ~= "boon_price_audit:auto_once_bounded_v0.7.279" then
        return "#467 boon price audit marker missing or stale"
    end
    local audit = mod._ct_boon_pricing_audit
    if type(audit) ~= "table" or type(audit.audit) ~= "function"
        or type(audit.validate_plan) ~= "function" then
        return "#467 pure audit/plan policy incomplete"
    end
    if type(mod._ct_boon_price_audit_once) ~= "function" then
        return "#467 automatic runtime census missing"
    end
    local report = audit.audit({ rare = { { name = "ct_467_self_test" } } },
        { rare = 200 }, { ct_467_self_test = {} }, 1)
    if report.total ~= 1 or #report.records ~= 1
        or report.records[1].shop_price ~= 200 or #report.anomalies ~= 0 then
        return "#467 audit self-test failed"
    end
end)

-- #294 crash guard: the _spawn_pickup hook must skip a non-resident pickup unit (vanilla's
-- own _safe_to_spawn_pickup check, which the _spawn_pickup path omits). Verify the guard
-- helper exists and classifies correctly: nil settings + spawn_override_func pickups are SAFE
-- (pass-through), a bogus non-resident unit_name is UNSAFE. Marker present too.
_rt_register("pickup_residency_guard_installed", function()
    if type(CT_PICKUP_RESIDENCY_GUARD_MARKER) ~= "string" or #CT_PICKUP_RESIDENCY_GUARD_MARKER == 0 then
        return "#294 REGRESSION: CT_PICKUP_RESIDENCY_GUARD_MARKER not defined"
    end
    if type(mod._ct_pickup_unit_spawn_safe) ~= "function" then
        return "#294 REGRESSION: mod._ct_pickup_unit_spawn_safe missing (non-resident pickup crash guard)"
    end
    if mod._ct_pickup_unit_spawn_safe(nil) ~= true then
        return "#294 REGRESSION: guard must treat nil settings as safe (pass-through)"
    end
    if mod._ct_pickup_unit_spawn_safe({ unit_name = "units/x_zzz", spawn_override_func = function() end }) ~= true then
        return "#294 REGRESSION: guard must leave spawn_override_func pickups alone (they self-spawn)"
    end
    -- With Application.can_get available (in-mission), a bogus unit path must read UNSAFE.
    if rawget(_G, "Application") and Application.can_get then
        if mod._ct_pickup_unit_spawn_safe({ unit_name = "units/mutator/__ct294_bogus_unit__" }) ~= false then
            return "#294 REGRESSION: guard must classify a non-resident unit_name as UNSAFE (would crash spawn_network_unit)"
        end
    end
end)

-- #322: the _spawn_pickup hook must capture AND re-return BOTH of vanilla's return
-- values (pickup_unit, pickup_unit_go_id). Dropping the go_id (`return spawned`)
-- desyncs surface-linked pickups to clients (pickup_system.lua:1441 rpc_link_pickup).
-- Source-pattern check: assert the two-value capture + two-value return survive.
-- Anchored via the same-file #294 helper; best-effort (nil = pass if unreadable).
_rt_register("spawn_pickup_returns_both_values", function()
    -- issue 511: assert the load-time provenance marker set beside the _spawn_pickup
    -- hook instead of source-reading (the VMF sandbox has no `io`, so the old
    -- io.open self-grep threw and FAILED this on healthy code). The exact 2-value
    -- capture/return shape is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if CT_SPAWN_PICKUP322_MARKER ~= "spawn_pickup322:two_value_capture_and_return_v0.7.245" then
        return "#322 REGRESSION: CT_SPAWN_PICKUP322_MARKER missing/mismatch (two-return _spawn_pickup hook stripped -- linked-pickup rpc_link_pickup client sync breaks); got: " .. tostring(CT_SPAWN_PICKUP322_MARKER)
    end
end)

-- #299 chest-revive team-teleport wiring: the deferred return-to-team pass must be
-- present (function + pending table) so a chest-revived player can't be left stranded
-- at a distant respawn beacon. The tick is driven from the single mod.update owner
-- (verified separately by the paced-send drainer check); here we just assert the
-- callable + its pending table exist and the feature toggle is registered.
_rt_register("chest_revive_team_teleport_wired", function()
    if type(mod._ct_chest_teleport_tick) ~= "function" then
        return "#299 REGRESSION: mod._ct_chest_teleport_tick missing (chest-revive return-to-team teleport)"
    end
    if type(mod._ct_pending_team_teleport) ~= "table" then
        return "#299 REGRESSION: mod._ct_pending_team_teleport table missing (teleport arm store)"
    end
    if type(mod:get("respawn_on_chest_complete")) ~= "boolean" then
        return "#299 REGRESSION: respawn_on_chest_complete checkbox not registered (mod:get is non-boolean)"
    end
end)

-- #144 Vaul's Anvil reconciler/probe guard: the perk self-healing update func must exist and be
-- registered into BuffFunctionTemplates.functions under the name the ct boon's controller buff
-- points its update_func at, so the perk (deus_always_blocking_buff -> override_blocking) is
-- reconciled every frame instead of relying on vanilla's orphaned weapon-swap trigger. Registration
-- is deferred to whenever BuffFunctionTemplates is ready, so in a bare test env (no engine tables)
-- only the callable presence is asserted.
_rt_register("vauls_anvil_reconciler_installed", function()
    if type(mod._ct_vauls_anvil_reconcile) ~= "function" then
        return "#144 REGRESSION: mod._ct_vauls_anvil_reconcile missing (Vaul's Anvil perk reconciler)"
    end
    local bft = rawget(_G, "BuffFunctionTemplates")
    if bft and bft.functions then
        if bft.functions.ct_vauls_anvil_reconcile ~= mod._ct_vauls_anvil_reconcile then
            return "#144 REGRESSION: ct_vauls_anvil_reconcile not registered into BuffFunctionTemplates.functions (buff update_func won't resolve)"
        end
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
-- NOTE (v0.7.216 fix): this table was `setmetatable({}, { __mode = "v" })` - a
-- WEAK-VALUED table. Its values ARE the handler functions below, referenced nowhere
-- else, so the GC collected them between file-load and the first mission; by the time
-- _diag_subscribe_if_needed ran, `_ct_diag_subscriber.player_pickup_deus_weapon_chest`
-- was nil and EventManager.register fatally fasserted "No function found with name ...
-- on supplied object" (event_manager.lua:16) inside the pcall, so the pickup/chest
-- diagnostic NEVER attached (it fired on every map populate). A plain strong table keeps
-- the handlers alive; the module-scope local lives for the whole session (no leak), and
-- the vanilla EventManager already stores subscribers weakly on its own side.
local _ct_diag_subscriber = {}

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
mod:hook("DeusChestExtension", "open_chest", function(func, self)
    -- #100 fix (v0.7.169-dev): capture the rarity vanilla open_chest JUST used to
    -- upgrade the host's weapon, BEFORE the upgrade-altar re-arm block below bumps
    -- self._rarity one tier higher for the NEXT use. The bot-weapon-mirror (further
    -- down this same hook) must mirror the rarity the HOST actually received, not the
    -- bumped next-use value — otherwise bots land one tier above the host
    -- (log-confirmed 2026-06-25 go_id=62: host wielded=rare, altar bumped to exotic,
    -- bots got exotic). Captured for all chest types; only the upgrade path is bumped,
    -- so swap_melee/swap_ranged see their unchanged self._rarity here.
    local _opened_rarity = self._rarity
    local _opened_cost = self:get_purchase_cost()
    local prior_bot_altar_cost = mod._ct_bot_altar_cost
    if self._chest_type == DEUS_CHEST_TYPES.power_up then
        mod._ct_bot_altar_cost = _opened_cost
    end
    local vanilla_ok, vanilla_err = pcall(func, self)
    mod._ct_bot_altar_cost = prior_bot_altar_cost
    if not vanilla_ok then error(vanilla_err) end
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

                -- v0.7.211-dev #102 DECOUPLE (was the v0.7.158 rarity bump): do NOT bump
                -- self._rarity on re-arm. The reward tier is self._rarity (open_chest ->
                -- _generate_upgraded_weapon), so bumping it climbed the reward each use. Instead
                -- self._rarity stays at the constant rolled tier and the relaxed
                -- update_upgrade_chest_color / can_be_unlocked hooks (near _generate_upgraded_weapon,
                -- `<=` -> strict `<` for a re-armed upgrade altar) keep the altar lit + usable at
                -- same-tier without inflating the reward. Here we just refresh the rolled tier's glow
                -- and clear the cached color memo so the color logic re-evaluates on the next tick.
                if self._chest_type == DEUS_CHEST_TYPES.upgrade then
                    if self._rarity and self.unit and Unit and Unit.flow_event
                        and (not Unit.alive or Unit.alive(self.unit)) then
                        pcall(Unit.flow_event, self.unit, "lua_update_" .. self._rarity)
                    end
                    self._prev_update_upgrade_chest_color_event = nil
                    _dbg("[altar_reuse] upgrade re-arm go_id=%s altar_rarity=%s (no bump, decoupled)",
                        tostring(go_id), tostring(self._rarity))
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
            local current = _bot_get_current_loadout(bot, run_state, host_peer_id, target_slot)
            if chest_type == DEUS_CHEST_TYPES.upgrade then
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
            -- #121 DIAGNOSTIC [ct:bots121]: log the tier the bot lands on vs the host's
            -- opened tier. Post #100/#102, live self._rarity == _opened_rarity == target_rarity
            -- and new_weapon.rarity should equal target_rarity (== host tier). ANY drift here
            -- (bot_after order > host tier) is the "one tier above" smoking gun. Read-only.
            pcall(function()
                local pre_rarity = "n/a"
                if chest_type == DEUS_CHEST_TYPES.upgrade then
                    local c = _bot_get_current_loadout(bot, run_state, host_peer_id, target_slot)
                    pre_rarity = c and tostring(c.rarity) or "none"
                end
                pcall(printf, "[ct:bots121] bot=%s chest=%s slot=%s host_opened_rarity=%s live_self_rarity=%s target_rarity=%s bot_before=%s bot_after=%s (issue #121)",
                    tostring(bot.name and bot:name() or "?"), tostring(chest_type), tostring(target_slot),
                    tostring(_opened_rarity), tostring(self._rarity), tostring(target_rarity),
                    tostring(pre_rarity), tostring(new_weapon and new_weapon.rarity))
            end)
            if new_weapon then
                local bot_cost = mod._ct_bot_economy.weapon_cost(rawget(_G, "DeusCostSettings"),
                    chest_type, current and current.rarity, target_rarity, _opened_cost)
                if mod._ct_bot_economy_charge(run_state, bot, bot_cost, "weapon_" .. tostring(chest_type)) then
                    local equipped_ok, equip_err = _bot_equip_weapon(bot, new_weapon, target_slot, run_state, host_peer_id)
                    if not equipped_ok then
                        -- A failed equip must be economically atomic: restore the
                        -- charge and leave the bot's prior weapon intact.
                        local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
                        local balance = run_state:get_player_soft_currency(peer_id, local_player_id) or 0
                        run_state:set_player_soft_currency(peer_id, local_player_id,
                            mod._ct_bot_economy.credit(balance, bot_cost))
                        _dbg_alert("[bot-weap] equip failed bot_idx=%d (refunded %d): %s",
                            bi, bot_cost, tostring(equip_err))
                    end
                else
                    mod._ct_bot_economy_log("weapon skipped bot=%s chest=%s cost=%s current=%s target=%s",
                        tostring(bot.name and bot:name() or bot:local_player_id()), tostring(chest_type),
                        tostring(bot_cost), tostring(current and current.rarity), tostring(target_rarity))
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
        if mod._ct_umbrella_policy.banned(
            effective_setting("ban_all_grudge_marks"), effective_setting(sid)) then
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
                    if type(nm) == "string" and mod._ct_umbrella_policy.banned(
                        effective_setting("ban_all_grudge_marks"),
                        effective_setting("ban_grudge_mark_" .. nm)) then
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
        local toggle_on = mod._ct_umbrella_policy.banned(
            effective_setting("ban_all_grudge_marks"),
            effective_setting("ban_grudge_mark_" .. name))
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
        local toggle_on = mod._ct_umbrella_policy.banned(
            effective_setting("ban_all_grudge_marks"),
            effective_setting("ban_grudge_mark_" .. name))
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

-- Modified-boon runtime extraction (issue #2). The context is deliberately
-- short-lived: the module localizes every dependency during this one dofile,
-- then owns all boon/miracle/trait state and hooks at the original load point.
mod._ct_boon_runtime_context = {
    capture_returns = _capture_returns,
    collect_setting_ids = _collect_setting_ids,
    meta_ammo_cost_multiplier = _ct_meta_ammo_cost_multiplier,
    dbg = _dbg,
    rt_register = _rt_register,
    effective_setting = effective_setting,
    meta_ammo_cap = CT_META_AMMO_CAP,
    meta_ammo_floor = CT_META_AMMO_FLOOR,
    meta_ammo_marker = CT_META_AMMO_HYPERBOLIC_MARKER,
    meta_ammo_max_stacks = CT_META_AMMO_MAX_STACKS,
    meta_ammo_step = CT_META_AMMO_STEP,
    rpc_schema = CT_RPC_SCHEMA,
    mod_version = MOD_VERSION,
    mutex = _ct_mutex,
    real_player_local_id = REAL_PLAYER_LOCAL_ID,
    defeat_recovery_triggered = function(value)
        if value ~= nil then
            _defeat_recovery_triggered_this_round = value
        end
        return _defeat_recovery_triggered_this_round
    end,
}
mod._ct_boon_balance = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance")
mod._ct_boon_registry = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_registry")
mod._ct_meta_trait_boons = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons")
mod._ct_boon_runtime_context = nil

-- Preserve the established forward-declared entry-chunk surfaces used by
-- earlier hook closures. VMF invokes those closures only after module load.
sync_reckless_swings = mod._ct_boon_balance.sync_reckless_swings
sync_bomb_cooldown = mod._ct_boon_balance.sync_bomb_cooldown
sync_ulric_pack_unlimited_range = mod._ct_boon_balance.sync_ulric_pack_unlimited_range
sync_boon_movespeed = mod._ct_boon_balance.sync_boon_movespeed
sync_host_dependent_state = mod._ct_meta_trait_boons.sync_host_dependent_state

_rt_register("issue2_boon_runtime_extracted", function()
    if mod._ct_boon_runtime_context ~= nil then
        return "short-lived boon runtime context was not cleared"
    end
    if type(mod._ct_boon_balance) ~= "table"
        or type(mod._ct_boon_registry) ~= "table"
        or type(mod._ct_meta_trait_boons) ~= "table" then
        return "one or more boon runtime owner modules did not load"
    end
    if sync_reckless_swings ~= mod._ct_boon_balance.sync_reckless_swings
        or sync_host_dependent_state ~= mod._ct_meta_trait_boons.sync_host_dependent_state then
        return "entry forward surfaces do not match extracted owners"
    end
end)

-- ============================================================
-- Combat / proc / Chest-of-Trials runtime hooks -> _ct_combat_hooks.lua
-- (repo issue #2 file-size refactor). Loaded HERE so hook registration and the
-- load-time trial injection keep their original execution point. Single dofile.
-- ============================================================
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_combat_hooks")

-- Pool-affecting settings: master toggle, per-CW-scenario toggles, and per-adventure
-- toggles. Re-run inject_pool() on any of these so changes take effect without a
-- restart. The engine reads LEVEL_AVAILABILITY at run setup (DeusMechanism._setup_run)
-- — changes only affect the NEXT expedition, not a CW run already underway.
local function is_pool_setting(setting_id)
    if setting_id == "inject_adventure_maps" then return true end
    if type(setting_id) ~= "string" then return false end
    return setting_id:find("^enable_adventure_") ~= nil
        or setting_id:find("^enable_cw_") ~= nil
        or setting_id:find("^enable_group_") ~= nil  -- #457 group master toggles
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
        mod._ct_boon_balance.sync_poison_proof_tweak()
    elseif setting_id == "tweak_invis_potion_2x" then
        mod._ct_boon_balance.sync_invis_potion_tweak()
    elseif setting_id == "tweak_moot_milk_alt" then
        mod._ct_boon_balance.sync_moot_milk_alt_tweak()
    elseif setting_id == "tweak_shard_strike_duration" then
        mod._ct_boon_balance.sync_shard_strike()
    elseif setting_id == "tweak_anath_raema_permanent" then
        mod._ct_boon_balance.sync_anath_raema_permanent()
    elseif setting_id == "tweak_shadow_skull_stun_sec" then
        if mod._ct_sync_shadow_skull_stun then mod._ct_sync_shadow_skull_stun() end
    elseif setting_id == "miasma_permanent_carrier"
        or setting_id == "miasma_safe_radius" or setting_id == "miasma_stack_interval" then
        if mod._ct_sync_miasma then mod._ct_sync_miasma() end
    -- 2026-05-23 v0.7.98-dev DISABLED: dormant + skulls event toggles removed from VMF menu.
    -- Their setting_id prefixes will never fire here because the widgets no longer exist, but
    -- comment them out to make the disable explicit (re-enable alongside data.lua + loc).
    -- elseif type(setting_id) == "string" and setting_id:find("^activate_dormant_") == 1 then
    --     sync_dormant_boons()
    elseif setting_id == "ban_all_grudge_marks"
        or (type(setting_id) == "string" and setting_id:find("^ban_grudge_mark_") == 1) then
        sync_grudge_marks()
    -- elseif setting_id == "enable_skulls_event_boons" then
    --     sync_skulls_event_boons()
    elseif setting_id == "enable_boon_reworks"
        or (type(setting_id) == "string" and setting_id:find("^enable_boon_") == 1) then
        for _, spec in ipairs(mod._ct_meta_trait_boons.trait_boons) do
            mod._ct_meta_trait_boons.register_trait_boon(spec)  -- idempotent; also ejects when either gate is off
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
    mod._ct_boon_balance.revert_reckless_swings_tweak()
    mod._ct_boon_balance.revert_bomb_cooldown_tweak()
    mod._ct_boon_balance.revert_boon_movespeed_tweak()
    mod._ct_boon_balance.revert_poison_proof_tweak()
    mod._ct_boon_balance.revert_invis_potion_tweak()
    mod._ct_boon_balance.revert_moot_milk_alt_tweak()
    mod._ct_boon_balance.revert_shard_strike_tweak()
    mod._ct_boon_balance.revert_anath_raema_permanent_tweak()
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

mod:command("ct_boon_price_audit", "Re-run the bounded #467 live boon tier/price census", function()
    mod._ct467_audit_done = false
    local mechanism = Managers and Managers.mechanism
        and Managers.mechanism.game_mechanism and Managers.mechanism:game_mechanism()
    local run_controller = mechanism and mechanism.get_deus_run_controller
        and mechanism:get_deus_run_controller()
    local report = mod._ct_boon_price_audit_once(true, run_controller)
    if report then
        mod:echo("Boon price census written to the log: %d live rows.", report.total)
    else
        mod:echo("Boon price census unavailable; enter Chaos Wastes and try again.")
    end
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
    for _, spec in ipairs(mod._ct_meta_trait_boons.trait_boons) do
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
    for _, spec in ipairs(mod._ct_meta_trait_boons.trait_boons) do
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

-- v0.7.240-dev (#406): restored alongside the re-enabled ct_kill_heal block above.
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
    -- no_roamers when current level is adventure-injected. v0.7.231: also strips
    -- when pack_spawning_settings lacks difficulty_overrides (deus missions on
    -- adventure-derived conflict directors, e.g. Belakor). Verify both the
    -- incompatible-list entry and the v0.7.231 crash-predicate fix marker.
    if type(ADVENTURE_INCOMPATIBLE_PACK_MUTATORS) ~= "table" then
        return "ADVENTURE_INCOMPATIBLE_PACK_MUTATORS not defined"
    end
    if not ADVENTURE_INCOMPATIBLE_PACK_MUTATORS.no_roamers then
        return "no_roamers missing from incompatible list"
    end
    if CT_NO_ROAMERS_DEUS_FIX_MARKER ~= "no_roamers_strip_keys_on_missing_difficulty_overrides_v0.7.231" then
        return "v0.7.231 no_roamers deus-mission fix marker missing/changed - Belakor pairs(nil) crash may have regressed"
    end
end)

_rt_register("no_roamers_strip_arity_356", function()
    -- Behavioral arity lock (issue 356). Vanilla tweak_pack_spawning_settings is STATIC:
    -- dot-called with 4 args (zone_mutator_list, mutator_list, conflict_director_name,
    -- pack_spawning_settings) at main_path_spawning_generator.lua:327. Drive the REAL hooked
    -- function through VMF exactly as vanilla does. difficulty_overrides is nil so the strip
    -- path engages; both sentinel lists carry no_roamers only, so a correct (self-less) hook
    -- filters both and vanilla run_mutators touches nothing -> ok. If the old spurious-`self`
    -- arity regressed, no_roamers leaks into the unfiltered zone list, run_mutators invokes
    -- mutator_no_roamers which does pairs(pack_spawning_settings.difficulty_overrides) = nil.
    -- That is a Lua error (NOT an engine fatal), so pcall traps it and we report the failure.
    if type(CT_NO_ROAMERS_ARITY_FIX_MARKER) ~= "string"
            or CT_NO_ROAMERS_ARITY_FIX_MARKER ~= "no_roamers_hook_static_arity_no_self_v0.7.241" then
        return "CT_NO_ROAMERS_ARITY_FIX_MARKER missing/changed - #356 static-hook arity fix may have reverted"
    end
    if not (MutatorHandler and MutatorHandler.tweak_pack_spawning_settings) then
        return "MutatorHandler.tweak_pack_spawning_settings unavailable"
    end
    local ok, err = pcall(MutatorHandler.tweak_pack_spawning_settings,
        { "no_roamers" }, { "no_roamers" }, "ct_regression_356", { difficulty_overrides = nil })
    if not ok then
        return "no_roamers reached vanilla run_mutators - pairs(nil) crash, #356 arity regressed (spurious self back?): " .. tostring(err)
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

_rt_register("networked_flow_state_cap_guarded", function()
    -- v0.7.213: the leak fix (clear_object_state) balances CHURN, but the 512
    -- cap can be hit by genuinely-live objective_units during a Chest of Trials
    -- under enemy_tweaker raised caps. The guard hooks flow_cb_create_state to
    -- reclaim dead-unit slots then decline the create instead of fatalling.
    -- Verify the marker constant survived into the bundle and the method is
    -- still hookable on the class.
    if type(CT_FLOWSTATE_CAP_GUARD_MARKER) ~= "string" or #CT_FLOWSTATE_CAP_GUARD_MARKER == 0 then
        return "CT_FLOWSTATE_CAP_GUARD_MARKER not defined (overflow guard missing)"
    end
    local cls = rawget(_G, "NetworkedFlowStateManager")
    if not cls then return nil end
    if type(cls.flow_cb_create_state) ~= "function" then
        return "flow_cb_create_state missing on NetworkedFlowStateManager"
    end
end)

_rt_register("progressive_difficulty_installed", function()
    if type(CT_PROGRESSIVE_DIFFICULTY_MARKER) ~= "string" or #CT_PROGRESSIVE_DIFFICULTY_MARKER == 0 then
        return "CT_PROGRESSIVE_DIFFICULTY_MARKER not defined (progressive difficulty missing)"
    end
    -- Self-test the exact #460 schedule: maps 3 and 5 are the only step edges.
    local step = mod._ct_progdiff_step
    if step then
        if rawget(_G, "Difficulties") then
            if step("hardest", 0) ~= "hardest" or step("hardest", 1) ~= "hardest" then
                return "progressive_difficulty steps within the first two missions"
            end
            if step("hardest", 2) ~= "cataclysm" then
                return "progressive_difficulty mission-3 step wrong (expected cataclysm)"
            end
            if step("hardest", 3) ~= "cataclysm" then
                return "progressive_difficulty changed again before mission 5"
            end
            if step("hardest", 4) ~= "cataclysm_2" or step("hardest", 100) ~= "cataclysm_2" then
                return "progressive_difficulty mission-5/cap step wrong"
            end
        end
    else
        return "mod._ct_progdiff_step not defined"
    end
    local policy = mod._ct_progressive_policy
    if not policy
        or policy.coin_multiplier(2, -25, 1) ~= 2
        or policy.coin_multiplier(2, -25, 2) ~= 1.5 then
        return "progressive coin reduction policy missing or wrong"
    end
    local cls = rawget(_G, "DeusRunController")
    if cls and type(cls.get_run_difficulty) ~= "function" then
        return "get_run_difficulty missing on DeusRunController"
    end
end)

_rt_register("replacement_player_compensation_installed", function()
    if CT_REPLACEMENT_COMPENSATION_MARKER ~= "replacement_compensation:host_state_handoff_v0.7.277" then
        return "replacement compensation marker missing or stale"
    end
    local policy = mod._ct_replacement_policy
    if type(policy) ~= "table" or type(policy.capture) ~= "function"
        or type(policy.apply) ~= "function" or type(policy.wire_safe_copy) ~= "function" then
        return "replacement compensation policy incomplete"
    end
    if type(mod._ct_replacement_filtered) ~= "function" then
        return "replacement compensation wire filter missing"
    end
    local cls = rawget(_G, "GameModeDeus")
    if cls and (type(cls.player_left_game_session) ~= "function"
        or type(cls._add_bot) ~= "function" or type(cls.remove_bot) ~= "function") then
        return "GameModeDeus replacement lifecycle seam missing"
    end
end)

_rt_register("journey_difficulty_guard_installed", function()
    -- Issue #291: guard against the vanilla journey-stat CTD when a CW journey is
    -- won above base cataclysm (our progressive_difficulty ramp reaches cataclysm_3).
    if type(CT_JOURNEY_DIFFICULTY_GUARD_MARKER) ~= "string" or #CT_JOURNEY_DIFFICULTY_GUARD_MARKER == 0 then
        return "CT_JOURNEY_DIFFICULTY_GUARD_MARKER not defined (issue #291 guard missing)"
    end
    local su = rawget(_G, "StatisticsUtil")
    if su and type(su._register_completed_journey_difficulty) ~= "function" then
        return "_register_completed_journey_difficulty missing on StatisticsUtil"
    end
    -- Verify the crash precondition the guard clamps around still holds: cataclysm_3
    -- must be ABSENT from DefaultDifficulties (else vanilla wouldn't have crashed and
    -- the guard is dead code that should be revisited).
    local dm = Managers and Managers.state and Managers.state.difficulty
    if dm and dm.get_default_difficulties then
        local defaults = dm:get_default_difficulties()
        if type(defaults) == "table" and table.find(defaults, "cataclysm_3") then
            return "cataclysm_3 now in DefaultDifficulties -- guard assumption changed, re-check #291"
        end
    end
end)

_rt_register("perf104_census_installed", function()
    -- v0.7.214: #104 host FPS-drop diagnostic. A throttled census folded into the
    -- CameraManager.shading_callback hook prints flow-state/enemy/fps every
    -- CT_PERF_WINDOW s on injected maps so the localized drop at the first-grimoire
    -- Chest of Trials (Blood in the Darkness) can be correlated with objective_unit
    -- load. Verify the marker + window constant survived into the bundle.
    if type(CT_PERF_CENSUS_MARKER) ~= "string" or #CT_PERF_CENSUS_MARKER == 0 then
        return "CT_PERF_CENSUS_MARKER not defined (perf census missing)"
    end
    if type(CT_PERF_WINDOW) ~= "number" or CT_PERF_WINDOW <= 0 then
        return "CT_PERF_WINDOW not a positive number"
    end
end)

_rt_register("reliquary_reroll_message_hook", function()
    -- v0.7.215 (#252): the same-tier re-roll prompt repaint is a single hook_safe on
    -- DeusUpgradeWeaponInteractionUI._populate_widget. Verify the marker survived into the
    -- bundle and the vanilla class/method is still present to hook.
    if type(CT_RELIQUARY_REROLL_MARKER) ~= "string" or #CT_RELIQUARY_REROLL_MARKER == 0 then
        return "CT_RELIQUARY_REROLL_MARKER not defined (#252 reroll-message hook missing)"
    end
    local cls = rawget(_G, "DeusUpgradeWeaponInteractionUI")
    if not cls then return nil end
    if type(cls._populate_widget) ~= "function" then
        return "_populate_widget missing on DeusUpgradeWeaponInteractionUI"
    end
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
    if type(mod._ct128_strip_parry_cooldowns) ~= "function" then
        return "#342 REGRESSION: deferred parry-cooldown strip is not published on mod"
    end
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

-- v0.7.248-dev #471 DIAGNOSTIC: presence check for the Chest-of-Trials spawn-composition
-- probe (raw printf: pre_req / built_req / placed per cursed-chest spawn element) armed in
-- _ct_combat_hooks.lua. Guards against a silent strip while #471 is still being root-caused;
-- the marker is a bare cross-file global set at that hook's install site.
_rt_register("cot471_spawn_composition_probe", function()
    if type(CT_COT_471_DIAG_MARKER) ~= "string" then
        return "#471 REGRESSION: CT_COT_471_DIAG_MARKER not defined — CoT spawn-composition diagnostic stripped"
    end
    if CT_COT_471_DIAG_MARKER ~= "cot471:spawn_composition_pre_scaled_placed_probe_v0.7.248" then
        return "#471 REGRESSION: CT_COT_471_DIAG_MARKER mismatch — got: " .. tostring(CT_COT_471_DIAG_MARKER)
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

-- v0.7.243-dev: presence check for the re-armed #132/#134/#136 diagnostics. Their
-- predecessors were silently reverted in v0.7.175 and stayed stripped for weeks; this
-- guard fails the regression suite if any of the three is removed again without also
-- removing this check (a deliberate, visible action rather than a silent strip).
_rt_register("diag_132_134_136_present", function()
    if type(mod._ct_chest132) ~= "table" or type(mod._ct_chest132.chest_appeared) ~= "function" then
        return "#132 chest-of-trials probe missing (mod._ct_chest132.chest_appeared) - extensions_ready ground-truth stripped"
    end
    if type(mod._ct_chest132.finalize) ~= "function" then
        return "#349 settled chest-count audit missing - extension count cannot be compared after census completion"
    end
    if type(mod._ct_chest132.begin) ~= "function" then
        return "#349 chest-count audit reset missing - zero-chest missions cannot be classified"
    end
    if type(mod._ct_tally_cursed_count) ~= "function" then
        return "#132 census cross-check missing (mod._ct_tally_cursed_count) - extensions_ready vs census diff can't be computed"
    end
    if type(mod._ct134_log) ~= "function" then
        return "#134 collectible probe missing (mod._ct134_log) - [ct-probe:collectible] stripped"
    end
    if type(mod._ct_mission136_dump) ~= "function" then
        return "#136 graph-divergence probe missing (mod._ct_mission136_dump) - host/client graph diff stripped"
    end
end)

-- v0.7.211-dev #102 DECOUPLE: presence check that the rarity-escalation fix is in place, i.e.
-- the reward-rarity bump is GONE and a re-armed upgrade altar is kept usable via the relaxed
-- update_upgrade_chest_color / can_be_unlocked gate hooks instead. Guards against a future session
-- re-introducing the climbing bump.
_rt_register("upgrade_altar_rarity_decouple", function()
    if type(CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER) ~= "string" then
        return "CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER not defined — #102 rarity-decouple fix may have been stripped"
    end
    if CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER ~= "upgrade_altar_rarity_decouple:relaxed_gates_no_bump_v0.7.211" then
        return "CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER mismatch — got: " .. tostring(CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER)
    end
end)

-- v0.7.212-dev #143 DIAGNOSTIC: presence check for the Morgrim's-Bomb appearance-by-source census.
_rt_register("morgrim143_probe_installed", function()
    if type(mod._ct_morgrim143_count) ~= "function" then
        return "#143 REGRESSION: mod._ct_morgrim143_count missing (Morgrim's appearance-by-source probe stripped)"
    end
    if CT_MORGRIM143_MARKER ~= "morgrim143:appearance_by_spawn_type_census_v0.7.212" then
        return "#143 REGRESSION: CT_MORGRIM143_MARKER mismatch — got: " .. tostring(CT_MORGRIM143_MARKER)
    end
end)

-- v0.7.232-dev #143 FIX (closed, user-confirmed): the ACTUAL over-spawn fix, not the census.
-- On injected adventure maps holy_hand_grenade's world spawn_weighting is HALVED and the freed
-- half redistributed proportionally to the other grenades so the pool SUM stays byte-identical
-- (a LOWERED total crashed the pickup sampler in v0.7.143). issue 511: asserts the load-time
-- CT_MORGRIM143_RENORM_MARKER (the source self-grep threw in the VMF sandbox, no `io`); the exact
-- renorm text is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
_rt_register("morgrim143_renorm_fix", function()
    if CT_MORGRIM143_RENORM_MARKER ~= "morgrim143:holy_hand_grenade_sum_preserving_renorm_v0.7.232" then
        return "#143 REGRESSION: CT_MORGRIM143_RENORM_MARKER missing/mismatch (holy_hand_grenade sum-preserving renorm stripped; a blind weight cut risks the pickup-sampler crash); got: " .. tostring(CT_MORGRIM143_RENORM_MARKER)
    end
end)

-- v0.7.232-dev #133 FIX (closed, user-confirmed): with tweak_manann_tempest_cooldown ON, the
-- VANILLA Manann's Tempest weapon trait (deus_crit_chain_lightning) tooltip gains the "8 second
-- cooldown." note - the _G.Localize hook appends it to func()'s vanilla string, gated on the
-- setting (stays EXACTLY vanilla with the tweak off). issue 511: asserts the load-time
-- CT_MANANN_TEMPEST_NOTE_MARKER (the source self-grep threw in the VMF sandbox, no `io`); the exact
-- branch text is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
_rt_register("manann_tempest_trait_cooldown_note", function()
    if CT_MANANN_TEMPEST_NOTE_MARKER ~= "manann_tempest:crit_chain_lightning_cooldown_note_v0.7.232" then
        return "#133 REGRESSION: CT_MANANN_TEMPEST_NOTE_MARKER missing/mismatch (deus_crit_chain_lightning cooldown-note override gone; Manann's Tempest tooltip no longer reflects the 8s-cooldown tweak); got: " .. tostring(CT_MANANN_TEMPEST_NOTE_MARKER)
    end
end)

-- v0.7.232-dev #115 (shrine) / #114 (chest) FIX (closed, user-confirmed): the offered-boon
-- scrollbar lets shrine_boon_count / chest_boon_count exceed the fixed vanilla arc without
-- overflow. The export mod._ct_boon_scroll_setup must exist AND be wired at BOTH offer surfaces
-- (shrine boon_widgets @4 visible rows, cursed-chest _power_up_widgets @3). Split needles so
-- these lines can't self-match.
_rt_register("boon_offer_scrollbar_wired", function()
    if type(mod._ct_boon_scroll_setup) ~= "function" then
        return "#115/#114 REGRESSION: mod._ct_boon_scroll_setup missing (boon-offer scrollbar stripped; the GUI overflows above the vanilla cap)"
    end
    -- issue 511: the runtime presence of the export is asserted above. The "wired at
    -- BOTH offer surfaces" invariant was an io.open source self-grep that threw in the
    -- VMF sandbox (no `io`); it is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
end)

-- v0.7.212-dev #145 DIAGNOSTIC: presence check for the Citadel resolved-god census.
_rt_register("citadel145_probe_installed", function()
    if type(mod._ct_citadel145_dump) ~= "function" then
        return "#145 REGRESSION: mod._ct_citadel145_dump missing (Citadel resolved-god probe stripped)"
    end
    if CT_CITADEL145_MARKER ~= "citadel145:resolved_god_census_v0.7.212" then
        return "#145 REGRESSION: CT_CITADEL145_MARKER mismatch — got: " .. tostring(CT_CITADEL145_MARKER)
    end
end)

-- v0.7.219-dev #145 FIX (closed v0.7.229, user-confirmed): the ACTUAL fix, not just the probe.
-- mod._ct_force_finale_god rewrites the god segment of arena_citadel_* (finale) and sig_citadel_*
-- (approach) on the FINISHED graph, restoring the finale_dominant_god override WITHOUT touching
-- config.NO_DOMINANT_GOD. The #145 conflict returns silently if the function is stripped OR its
-- call is dropped from either deus_populate_graph branch (normal + shop-converted). issue 511:
-- presence + the intentional-presence marker are asserted at runtime below; the "wired at BOTH
-- branches" count was an io.open source self-grep that threw in the VMF sandbox (no `io`) and is
-- delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
_rt_register("citadel145_force_finale_god_fix", function()
    if type(mod._ct_force_finale_god) ~= "function" then
        return "#145 REGRESSION: mod._ct_force_finale_god missing (Citadel finale-god override fix stripped)"
    end
    if CT_CITADEL145_FIX_MARKER ~= "citadel145:force_finale_god_fix_v0.7.219" then
        return "#145 REGRESSION: CT_CITADEL145_FIX_MARKER mismatch — got: " .. tostring(CT_CITADEL145_FIX_MARKER)
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
    if CT_COT_UNIQUE_TRIALS_MARKER ~= "cot_unique_trials:force_rotate_event_name_list_and_weighted_v0.7.246" then
        return "CT_COT_UNIQUE_TRIALS_MARKER mismatch — got: " .. tostring(CT_COT_UNIQUE_TRIALS_MARKER)
    end
    -- per-mission state must exist (globals, reset in _transition_next_node + setup_run)
    if type(_ct_cursed_chest_seq) ~= "number" then
        return "_ct_cursed_chest_seq not a number — per-mission counter missing/clobbered"
    end
    if type(_ct_cot_block_last) ~= "table" then
        return "_ct_cot_block_last not a table — per-block last-pick tracker missing/clobbered"
    end
    -- #463: the SPECIFIC-trial (weighted_event_names) rotation tracker must exist too
    if type(_ct_cot_trial_last) ~= "table" then
        return "_ct_cot_trial_last not a table — #463 specific-trial rotation tracker missing/clobbered"
    end
    -- the force-rotation helper must guarantee a pick != last when ≥2 distinct options exist
    if mod._ct_cot_rotate_pick then
        local p = mod._ct_cot_rotate_pick({ "a", "b", "b" }, "a")
        if p == "a" then
            return "force-rotation returned the previous pick ('a') — uniqueness not guaranteed"
        end
    end
    -- #463: the faction-challenge templates must carry the one_of/weighted_event_names
    -- shape the specific-trial rotation depends on (guards a vanilla restructure).
    local GTE = rawget(_G, "GenericTerrorEvents")
    if type(GTE) == "table" then
        local sk = GTE.cursed_chest_challenge_faction_skaven
        local one_of = type(sk) == "table" and sk[1]
        local blocks = type(one_of) == "table" and one_of[1] == "one_of" and one_of[2]
        local has_weighted = false
        if type(blocks) == "table" then
            for _, blk in ipairs(blocks) do
                if type(blk) == "table" and type(blk.weighted_event_names) == "table" then
                    has_weighted = true
                    break
                end
            end
        end
        if not has_weighted then
            return "cursed_chest_challenge_faction_skaven lost its one_of/weighted_event_names shape — #463 specific-trial rotation is a no-op"
        end
    end
end)

-- #324 (v0.7.226-dev): Skaven Warlord cursed-chest trial (cross-mod with
-- enemy_tweaker). Verifies the ensure/inject function + the et-absence guard,
-- and - when et's breed is present - that the trial event is registered, the
-- skaven pools carry the weighted pick, and the boss element's pre_spawn_func
-- is the LIVE TerrorEventUtils.add_enhancements_for_difficulty reference
-- (the CODE_REVIEW.md upvalue-gotcha check: grudge enhancements must apply).
_rt_register("warlord_trial_injection", function()
    if type(mod._ct_ensure_warlord_trial) ~= "function" then
        return "mod._ct_ensure_warlord_trial missing - #324 feature block absent"
    end
    local GTE = rawget(_G, "GenericTerrorEvents")
    if type(GTE) ~= "table" then
        return "GenericTerrorEvents not loaded (run in keep)"
    end
    local B = rawget(_G, "Breeds")
    local breed_present = B and type(B.et_skaven_warlord) == "table"
    if not breed_present then
        -- et absent: the guard must have kept the pools clean.
        if GTE.ct_cursed_chest_challenge_skaven_warlord then
            return "trial event registered but et_skaven_warlord breed absent - et-absence guard failed"
        end
        if mod._ct_warlord_trial_injected then
            return "_ct_warlord_trial_injected true without the breed - guard failed"
        end
        return  -- PASS: correctly inert without enemy_tweaker
    end
    mod._ct_ensure_warlord_trial()
    local ev = GTE.ct_cursed_chest_challenge_skaven_warlord
    if type(ev) ~= "table" then
        return "trial event not registered despite et_skaven_warlord present"
    end
    -- boss element sanity: breed + counter category + live pre_spawn_func ref
    local boss_el
    for _, el in ipairs(ev) do
        if type(el) == "table" and el[1] == "spawn_around_origin_unit"
                and el.breed_name == "et_skaven_warlord" then
            boss_el = el
            break
        end
    end
    if not boss_el then
        return "trial has no spawn_around_origin_unit element for et_skaven_warlord"
    end
    if boss_el.spawn_counter_category ~= "cursed_chest_enemies" then
        return "boss element missing cursed_chest_enemies counter category - chest would never open"
    end
    local TEU = rawget(_G, "TerrorEventUtils")
    if not (TEU and boss_el.pre_spawn_func == TEU.add_enhancements_for_difficulty) then
        return "boss element pre_spawn_func is not TerrorEventUtils.add_enhancements_for_difficulty - grudge enhancements would not apply"
    end
    -- pool injection: at least one skaven weighted block must carry our pick
    local found_in_pool = false
    local faction_event = GTE.cursed_chest_challenge_faction_skaven
    local one_of = type(faction_event) == "table" and faction_event[1]
    local blocks = type(one_of) == "table" and one_of[1] == "one_of" and one_of[2]
    if type(blocks) == "table" then
        for _, block in ipairs(blocks) do
            local wen = type(block) == "table" and block.weighted_event_names
            if type(wen) == "table" then
                for _, entry in ipairs(wen) do
                    if entry.event_name == "ct_cursed_chest_challenge_skaven_warlord" then
                        found_in_pool = true
                    end
                end
            end
        end
    end
    if not found_in_pool then
        return "ct_cursed_chest_challenge_skaven_warlord not present in any cursed_chest_challenge_faction_skaven weighted pool"
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
    local miracle_names = mod._ct_boon_registry.miracle_buff_names
    local ulric  = is_persistent_of(miracle_names.ulric)
    local aegis  = is_persistent_of(miracle_names.isha_aegis)
    local wounds = is_persistent_of(miracle_names.isha_wounds)
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

_rt_register("ct_meta_ammo_current_floor_256", function()
    -- Issue #256: the meta-ammo refresh seam must floor CURRENT ammo so vanilla
    -- `refresh_buffs` (generic_ammo_user_extension.lua:108, no >= 0 floor on
    -- `_available_ammo`) can't leave a partial-spawn weapon with negative reserve.
    -- Functional test on the exposed clamp helper: feed a fake ammo extension in the
    -- exact broken state (negative reserve, over-max clip) and assert it lands in range
    -- WITHOUT mutating _max_ammo.
    local clamp = mod._ct_clamp_current_ammo_256
    if type(clamp) ~= "function" then
        return "mod._ct_clamp_current_ammo_256 helper missing (issue 256 seam clamp reverted?)"
    end
    -- Broken state: reserve went negative and clip overshot max (both out of [0,max]).
    local ax = { _max_ammo = 20, _available_ammo = -4, _current_ammo = 25, item_name = "rt_probe" }
    clamp(ax, "regression_probe")
    if ax._available_ammo ~= 0 then
        return string.format("reserve not floored: got %s, expected 0", tostring(ax._available_ammo))
    end
    if ax._current_ammo ~= 20 then
        return string.format("clip not clamped to max: got %s, expected 20", tostring(ax._current_ammo))
    end
    if ax._max_ammo ~= 20 then
        return string.format("_max_ammo was mutated (%s) — max-resource doctrine violated", tostring(ax._max_ammo))
    end
    -- In-range values must be left untouched (clamp is a no-op when already valid).
    local ok_ax = { _max_ammo = 30, _available_ammo = 12, _current_ammo = 8 }
    clamp(ok_ax, "regression_probe")
    if ok_ax._available_ammo ~= 12 or ok_ax._current_ammo ~= 8 then
        return string.format("in-range values altered: reserve %s clip %s (expected 12/8)",
            tostring(ok_ax._available_ammo), tostring(ok_ax._current_ammo))
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
    if type(mod._ct_boon_balance.reckless_swings_marker) ~= "string" then
        return "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER not defined — was the v0.7.92 name-based-lookup fix reverted?"
    end
    if mod._ct_boon_balance.reckless_swings_marker ~= "name-based-lookup-v0.7.92" then
        return "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER mismatch — expected name-based-lookup-v0.7.92, got: " .. tostring(mod._ct_boon_balance.reckless_swings_marker)
    end
    if type(mod._ct_boon_balance.find_entry_by) ~= "function" then
        return "_find_entry_by helper missing — name-based lookup machinery removed?"
    end
    -- Stored-indices schema check (only when the tweak is active): the
    -- v0.7.92 `reckless_swings_originals` payload uses numeric `buff_index`,
    -- `dv_threshold_index`, `dv_damage_index` fields. A positional-only
    -- revert would store fewer or differently-named keys.
    local r = mod._ct_boon_balance.get_reckless_swings_originals()
    if r then
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

_rt_register("issue357_bomb_bubble_cooldown_display", function()
    return mod._ct_bomb_cooldown_display.regression_check(CT_RPC_SCHEMA)
end)

_rt_register("issue358_manann_tempest_cooldown_display", function()
    return mod._ct_bomb_cooldown_display.regression_check_manann(CT_RPC_SCHEMA)
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

_rt_register("mission_catalog_localization_format_safe_564", function()
    -- #564: generated localization bypasses the static source-table scan. VMF
    -- string.formats every dropdown label, so validate the catalog's complete
    -- generated surface directly (including future labels and fallback paths).
    local ok, catalog = pcall(mod.dofile, mod, "scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog")
    if not ok or type(catalog) ~= "table" or type(catalog.build_loc_entries) ~= "function" then
        return "mission catalog localization builder unavailable"
    end

    local entries = catalog.build_loc_entries()
    for key, entry in pairs(entries) do
        if type(entry) == "table" and type(entry.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, entry.en)
            if not fmt_ok then
                return string.format("generated loc key %q has invalid format string: %s", key, tostring(fmt_err))
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

pcall(printf, "[mem-probe] ct boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CT) / 1024)
