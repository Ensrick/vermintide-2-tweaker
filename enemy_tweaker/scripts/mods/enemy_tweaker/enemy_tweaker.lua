local mod = get_mod("enemy_tweaker")

local MOD_VERSION = "0.7.44-dev"
-- RPC schema version (VMF_RECIPES.md section 10, GitHub Issue #42). Prepended as
-- the FIRST positional arg of every mod:network_send this mod emits, and
-- validated as the first arg of every mod:network_register callback; a peer on a
-- different schema is dropped with a log line (no crash, no state mutation).
-- Bump ONLY when an RPC payload shape changes (field add/remove/reorder, or a
-- positional field's type changes). One constant per mod, shared across every
-- channel the mod owns. Never define below 1.
local ET_RPC_SCHEMA = 1
local _mem_probe_t0 = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([et:LOAD] v<X> enabled fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Enemy Tweaker v%s loaded", MOD_VERSION)

-- ============================================================
-- Module manifest (v0.7.31-dev structural split, PROJECT_STANDARDS § 2.2a)
-- ============================================================
-- This entry file owns MOD_VERSION (the launcher parses it from THIS file),
-- ET_RPC_SCHEMA, the load banner/LOAD/echo lines, and the dofile manifest.
-- All logic lives in single-responsibility `_et_*` modules in this directory.
--
-- Cross-module contract: `mod._et` is the shared namespace. Each module is
-- dofile'd EXACTLY ONCE, in the order below, and publishes its exports into
-- mod._et. VMF's mod:dofile is NOT a singleton -- every call re-executes the
-- file and returns a fresh value -- so modules must never dofile each other;
-- only this manifest loads them. Load order is load-bearing:
--   * _et_regression first (every later module registers its checks),
--   * _et_log before _et_protect (the protect wrappers alert through dbg_alert),
--   * data/state providers (presets/swaps/mimic/roaming/champion) before
--     _et_director_hooks, which re-applies them on ConflictDirector init/refresh,
--   * _et_skaven_warlord_breed MUST precede _et_champion_warlord: the new
--     breed deep-copies Breeds[skaven_storm_vermin_champion] and this order
--     guarantees the copy snapshots PRISTINE vanilla 800-HP champion values
--     even when champion_in_elite_pool is saved ON (#324),
--   * _et_lifecycle and _et_commands last among the new modules (they consume
--     everything), then the two pre-existing feature modules.
-- Regression checks print in registration order, so reordering this manifest
-- reorders /et_regression_test output (names are the frozen surface; the
-- v0.7.31-dev split moved each check into the module that owns what it checks,
-- so the print ORDER follows this manifest -- see CHANGELOG).
--
-- enemy_tweaker_big_rebalance.lua is DORMANT (BR on ice since bt retired
-- 2026-06-08; user decision #433 pending): it is deliberately NOT in this
-- manifest and NOT require()'d -- the stub in _et_fingerprint.lua preserves
-- its public API. Do not load, edit, or delete it without #433 being decided.
--
-- Data shared with enemy_tweaker_data.lua / _localization.lua lives in the
-- require()'d enemy_tweaker_breeds.lua module instead (VMF loads localization
-- -> data -> script, so nothing set here exists when those files evaluate).
mod._et = { version = MOD_VERSION, rpc_schema = ET_RPC_SCHEMA }

mod:dofile("scripts/mods/enemy_tweaker/_et_regression")           -- /et_regression_test harness + generic checks
mod:dofile("scripts/mods/enemy_tweaker/_et_log")                  -- logging helpers (dbg/alert/chat/spawn channels + printf probe)
mod:dofile("scripts/mods/enemy_tweaker/_et_protect")              -- protective wrappers (_safe/_hook_wrap/tick guard #479) + multiplier math
mod:dofile("scripts/mods/enemy_tweaker/_et_fingerprint")          -- BR + settings fingerprints, et_br_fingerprint RPC, dormant-BR stub
mod._et.SettingsQueue = mod:dofile("scripts/mods/enemy_tweaker/_et_settings_queue") -- #560 bounded setting-change transactions
mod._et.HealthMultiplierCore = mod:dofile("scripts/mods/enemy_tweaker/_et_health_multiplier_core") -- #369 engine-free bounds/policy
mod._et.SpecialVariantsCore = mod:dofile("scripts/mods/enemy_tweaker/_et_special_variants_core") -- #452 engine-free asset census
mod._et.EnemyModifiersCore = mod:dofile("scripts/mods/enemy_tweaker/_et_enemy_modifiers_core") -- #453 engine-free modifier census

-- Startup marker: unconditional mod:info (the "applied" log marker pattern).
-- Prefix changed v0.5.14 from [et:br] -> [et] to match the universal convention
-- (PROJECT_STANDARDS.md § 3.6). host_required=true retained as a per-mod addendum.
mod:info("[et:LOAD] v%s enabled fp=%s host_required=true OK",
    MOD_VERSION, mod._et.settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[et] v%s loaded", MOD_VERSION))
end

mod:dofile("scripts/mods/enemy_tweaker/_et_horde_presets")        -- horde preset catalog + composition backup/apply + CHS horde size
mod:dofile("scripts/mods/enemy_tweaker/_et_swaps")                -- breed/faction substitution + HordeSpawner hooks
mod:dofile("scripts/mods/enemy_tweaker/_et_mimic")                -- per-system difficulty mimic
mod:dofile("scripts/mods/enemy_tweaker/_et_roaming")              -- roaming size (SIP + recycler guard + ambient density + clone shim)
mod:dofile("scripts/mods/enemy_tweaker/_et_skaven_warlord_breed") -- #324 mod-added breed (MUST precede _et_champion_warlord)
mod:dofile("scripts/mods/enemy_tweaker/_et_champion_warlord")     -- champion/warlord pools + consolidated spawn hook + crash guards
mod:dofile("scripts/mods/enemy_tweaker/_et_director_hooks")       -- ConflictDirector init/refresh re-apply chain
mod:dofile("scripts/mods/enemy_tweaker/_et_event_size")           -- terror-event horde size scaling
mod:dofile("scripts/mods/enemy_tweaker/_et_pacing")               -- spawn pacing (CD tick #479 guard, freq/caps) + #213 freeze guard
mod:dofile("scripts/mods/enemy_tweaker/_et_banner")               -- beastman banner toggles
mod:dofile("scripts/mods/enemy_tweaker/_et_patrol")               -- patrol formation size
mod:dofile("scripts/mods/enemy_tweaker/_et_specials")             -- per-difficulty special spawns
mod:dofile("scripts/mods/enemy_tweaker/_et_health_multiplier")    -- #369 host-authoritative per-difficulty enemy health
mod:dofile("scripts/mods/enemy_tweaker/_et_lifecycle")            -- on_setting_changed / on_enabled / on_disabled + BR bootstrap
mod:dofile("scripts/mods/enemy_tweaker/_et_commands")             -- chat commands (/et_status, /verify_*, dumps, /et_reset)
mod:dofile("scripts/mods/enemy_tweaker/_et_boss_tweaks")          -- boss mechanic tweaks (fly-disable duration; pre-existing module)
mod:dofile("scripts/mods/enemy_tweaker/_et_boss_balance")         -- #450 per-boss balance toggles (health/armor/warp-lightning data mutations)
mod:dofile("scripts/mods/enemy_tweaker/_et_boss_grudge")          -- #531 grudge-mark behavioral knobs (Skarrik Berserk / Bodvarr Crippling, Cata+)
mod:dofile("scripts/mods/enemy_tweaker/_et_boss_ideas")           -- #451 bounded source/runtime feasibility audit; no unsafe arena-breed injection
mod:dofile("scripts/mods/enemy_tweaker/_et_special_variants")     -- #452 bounded premium-special asset audit; no breed/spawn mutation
mod:dofile("scripts/mods/enemy_tweaker/_et_enemy_modifiers")      -- #453 bounded modifier/template/category audit; no application yet

mod:info("[mem-probe] et boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _mem_probe_t0) / 1024)
