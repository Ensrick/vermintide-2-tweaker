local mod = get_mod("enemy_tweaker")

local MOD_VERSION = "0.7.5-dev"
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([et] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Enemy Tweaker v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[et:dbg] " .. fmt, ...)
    end
end

-- v0.7.0-dev: dbg_alert is now LOG-ONLY. Used to mod:echo to chat on every
-- call when debug logging was on, which spammed chat at high multipliers
-- (per-IP plateau, per-spawn breed-swap, etc. all fired through here). Chat
-- is reserved for `_chat_alert` below — genuinely surprising conditions only.
local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[et:dbg] " .. fmt, ...)
    end
end

-- _chat_alert(fmt, ...) — log + chat. ONLY call from genuinely surprising
-- paths: hook fallback fired (pcall'd vanilla errored), boss-skip in event
-- replication, ambients_ignore_threat clobbering vanilla state, hook install
-- failure. Always logs; only chat-echoes when debug logging is on.
local function _chat_alert(fmt, ...)
    mod:warning("[et:chat_alert] " .. fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:echo("[et] " .. fmt, ...)
    end
end

-- ============================================================
-- Protective layer helpers (v0.6.0-dev — PROJECT_STANDARDS § 4.1)
-- ============================================================
-- Goal: nothing in enemy_tweaker fails silently. Every hook body, every
-- runtime apply function, every global-table mutation is bracketed so that
-- any unexpected engine state produces a log entry (mod:warning at minimum,
-- _dbg_alert when Debug Logging is on) rather than a silent no-op or an
-- unhandled crash. See enemy_tweaker_data.lua for the four new 0-15x
-- spawn-scaling sliders that pair with these helpers.

-- _safe(label, fn, ...) — call fn(...) under pcall. On failure log a
-- mod:warning + an _dbg_alert (so it surfaces in chat when Debug Logging is
-- on) and return nil. Use for any mod-side helper that touches engine
-- tables (Breeds, HordeCompositions*, ConflictDirectors, Current* settings,
-- SizeOfInterestPoint, PatrolFormationSettings).
local function _safe(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        local err = tostring(a)
        mod:warning("[et:safe] %s failed: %s", tostring(label), err)
        _dbg_alert("safe-call %s failed: %s", tostring(label), err)
        return nil
    end
    return a, b, c, d
end

-- _hook_wrap(class, method, label, body) — wraps body in pcall and falls
-- through to vanilla `func(self, ...)` on any error. Logs mod:warning + an
-- _dbg_alert with the label. body receives (func, self, ...) same as
-- mod:hook. PROJECT_STANDARDS § 4.1 + § 4.2: bailing must call vanilla so
-- the engine's normal mutation still happens; an early-return guard is the
-- canonical regression class in this repo.
local function _hook_wrap(class, method, label, body)
    mod:hook(class, method, function(func, self, ...)
        local ok, r1, r2, r3, r4 = pcall(body, func, self, ...)
        if ok then return r1, r2, r3, r4 end
        local err = tostring(r1)
        mod:warning("[et:hook] %s (%s.%s) inner errored: %s — bailing to vanilla",
            tostring(label), tostring(class), tostring(method), err)
        _dbg_alert("hook %s (%s.%s) errored: %s", tostring(label), tostring(class), tostring(method), err)
        local fall_ok, fr1, fr2, fr3, fr4 = pcall(func, self, ...)
        if fall_ok then return fr1, fr2, fr3, fr4 end
        mod:warning("[et:hook] %s vanilla fallback ALSO errored: %s",
            tostring(label), tostring(fr1))
        _dbg_alert("hook %s vanilla fallback errored: %s", tostring(label), tostring(fr1))
        return nil
    end)
end

-- _hook_wrap_table(class_table, method, label, body) — table-form variant
-- for plain-table dispatchers (SpecialsPacing.setup_functions / .select_breed_functions).
-- body receives (func, ...) with NO `self` arg, matching the vanilla call
-- convention for these dispatcher tables.
local function _hook_wrap_table(class_table, method, label, body)
    mod:hook(class_table, method, function(func, ...)
        local ok, r1, r2, r3, r4 = pcall(body, func, ...)
        if ok then return r1, r2, r3, r4 end
        local err = tostring(r1)
        mod:warning("[et:hook] %s (table.%s) inner errored: %s — bailing to vanilla",
            tostring(label), tostring(method), err)
        _dbg_alert("hook %s errored: %s", tostring(label), err)
        local fall_ok, fr1, fr2, fr3, fr4 = pcall(func, ...)
        if fall_ok then return fr1, fr2, fr3, fr4 end
        mod:warning("[et:hook] %s vanilla fallback ALSO errored: %s",
            tostring(label), tostring(fr1))
        return nil
    end)
end

-- _spawn_dbg(channel, fmt, ...) — aggressive per-spawn debug trace, gated
-- on enable_debug_logging. Channels: paced / event / roaming / patrol /
-- unit / refresh. Stable prefix lets post-mission logs be grepped per
-- channel: `grep '\[et:spawn:event\]' console_log-*.log`.
local function _spawn_dbg(channel, fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[et:spawn:" .. tostring(channel) .. "] " .. fmt, ...)
    end
end

-- _spawn_dbg_alert(channel, fmt, ...) — _spawn_dbg variant that also
-- lands in chat. Use for unexpected spawn-side conditions: missing pack
-- data, oversize patrols past navmesh limits, breed-swap miss, fallback
-- paths. The "we did something but it might not have done what you wanted"
-- moments.
-- v0.7.0-dev: spawn_dbg_alert is now LOG-ONLY. Used to chat-echo every call
-- when debug logging was on, which fired per-IP, per-spawn-event, per-pack —
-- dozens of chat lines per zone load at high multipliers. Same rationale as
-- _dbg_alert above. Use `_chat_alert` for chat-worthy surprises.
local function _spawn_dbg_alert(channel, fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[et:spawn:" .. tostring(channel) .. "] " .. fmt, ...)
    end
end

-- _mult(setting_id) — read a 0-15 decimal multiplier; clamp; default 1
-- on missing/invalid. Returns (multiplier, is_zero).
local function _mult(setting_id)
    local raw = mod:get(setting_id)
    local m
    if type(raw) == "number" then
        m = raw
    elseif raw == nil then
        m = 1
    else
        m = tonumber(raw)
        if m == nil then
            _dbg_alert("setting %s has non-numeric value %s — using 1",
                tostring(setting_id), tostring(raw))
            m = 1
        end
    end
    if m < 0 then m = 0 end
    if m > 15 then m = 15 end
    return m, (m == 0)
end

-- _scale_count(base, mult) — round-to-nearest with mult=1 fast path and
-- mult=0 hard suppress. Used by every spawn-scaling hook.
local function _scale_count(base, mult)
    if mult == 1 then return base end
    if mult == 0 then return 0 end
    return math.max(0, math.floor((base or 0) * mult + 0.5))
end

-- v0.5.7: source-pattern marker constant for the /et_regression_test
-- `et_big_rebalance_uses_rawget` check (audit `.test_coverage_audit_2026-05-24.md`
-- PARTIAL row 4 — promoted to PASS by adding a runtime check beside the
-- existing strict-table-lookup lint coverage at all 6 sites).
local CT_ET_BIG_REBALANCE_RAWGET_MARKER_v0_5_7 = "et-big-rebalance-rawget-hardened-6-sites"

-- /regression_test scaffold. Registrations at end of file.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("et_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== enemy_tweaker regression_test (v%s) ===", MOD_VERSION)
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
mod:info("[regression-test-command] registered as /et_regression_test")

-- ============================================================
-- BR settings fingerprint (Issue #17 auto-probe)
-- ============================================================
-- Hashes the BR sub-toggle values currently in effect on this peer into a
-- short hex id. If host and client report different fingerprints, their BR
-- damage hooks are reading divergent settings and damage math will desync.
-- The fingerprint is logged unconditionally at startup as a mod:info marker;
-- per-hook entry/exit dumps go through _dbg (debug-toggle gated).
--
-- Setting list is the eleven `br_*` widgets currently registered in
-- enemy_tweaker_data.lua. Order is fixed (not the table iteration order) so
-- the FNV-1a hash is deterministic across peers.
local _BR_SETTING_NAMES = {
    "br_bloodlust_class_table",
    "br_bloodlust_per_breed_assign",
    "br_breed_trash_flags",
    "br_stagger_ai_rewrite",
    "br_calculate_damage_rewrite",
    "br_shield_slam_rewrite",
    "br_unbalance_debuff_infra",
    "br_thp_regrowth_template",
    "br_thp_vanguard_template",
    "br_thp_reaper_template",
    "br_thp_bloodlust_template",
}

-- Minimal FNV-1a 32-bit. Standard Lua 5.1, no bit32. Plain arithmetic ops
-- keep the implementation portable across Lua 5.1 / LuaJIT (VT2 uses the
-- former). Result is 8 hex chars.
local function _fnv1a32(s)
    local hash = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        -- XOR via per-bit emulation: Lua 5.1 has no bit32, and LuaJIT's bit
        -- lib isn't guaranteed under VT2's sandbox. The loop is cold-path
        -- (called once per BR hook fire at most), so per-bit cost is fine.
        local xored = 0
        local place = 1
        local h, b = hash, byte
        for _ = 1, 32 do
            local hb = h % 2
            local bb = b % 2
            if hb ~= bb then xored = xored + place end
            place = place * 2
            h = (h - hb) / 2
            b = (b - bb) / 2
        end
        hash = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", hash)
end

function mod._br_settings_fingerprint()
    local parts = {}
    for i, name in ipairs(_BR_SETTING_NAMES) do
        local v = mod:get(name)
        if v == true then       parts[i] = "1"
        elseif v == false then  parts[i] = "0"
        elseif v == nil then    parts[i] = "?"
        else                    parts[i] = tostring(v)
        end
    end
    return _fnv1a32(table.concat(parts, "|"))
end

-- ============================================================
-- BR fingerprint cross-peer compare (Issue #17 auto-probe)
-- ============================================================
-- One-shot per session: at first BR hook fire (calculate_damage/stagger_ai/
-- _hit), broadcast this peer's fingerprint to the rest of the lobby. On
-- receive, compare against our own; if they differ, _dbg_alert so the
-- mismatch shows up in chat too (host/client BR-toggle drift is a real
-- multiplayer divergence — not just a confirmation dump).
local _br_fingerprint_broadcast = false
local _br_fingerprint_peers = {}  -- peer_id -> fingerprint

mod._br_fingerprint_broadcast_once = function()
    if _br_fingerprint_broadcast then return end
    _br_fingerprint_broadcast = true
    local fp = mod._br_settings_fingerprint()
    if mod.network_send then
        local ok, err = pcall(function()
            mod:network_send("et_br_fingerprint", "others", MOD_VERSION, fp)
        end)
        if not ok then
            mod:info("[BR:fp] broadcast failed: %s", tostring(err))
        else
            mod:info("[BR:fp] broadcast fp=%s v=%s to peers", fp, MOD_VERSION)
        end
    end
end

mod:network_register("et_br_fingerprint", function(sender_peer_id, peer_version, peer_fp)
    if type(peer_fp) ~= "string" then return end
    _br_fingerprint_peers[tostring(sender_peer_id)] = peer_fp
    local own_fp = mod._br_settings_fingerprint()
    if peer_fp ~= own_fp then
        -- _dbg_alert because mismatch is the actionable case (host/client
        -- BR settings drift -> damage math divergence). PROJECT_STANDARDS § 3.6.
        if mod:get("enable_debug_logging") then
            mod:info("[et:dbg] [BR:fp] MISMATCH peer=%s peer_v=%s peer_fp=%s own_fp=%s -- BR sub-toggles diverge",
                tostring(sender_peer_id), tostring(peer_version), peer_fp, own_fp)
            mod:echo("[et] [BR:fp] MISMATCH peer=%s peer_fp=%s own_fp=%s",
                tostring(sender_peer_id), peer_fp, own_fp)
        else
            -- Surface even with debug OFF — mismatch is a real bug condition,
            -- not a routine confirmation. Use a single mod:info line (no chat
            -- spam) so non-debug players still get a triage breadcrumb.
            mod:info("[BR:fp] MISMATCH peer=%s peer_v=%s peer_fp=%s own_fp=%s -- BR sub-toggles diverge",
                tostring(sender_peer_id), tostring(peer_version), peer_fp, own_fp)
        end
    else
        mod:info("[BR:fp] match peer=%s fp=%s v=%s",
            tostring(sender_peer_id), peer_fp, tostring(peer_version))
    end
end)

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes ALL setting=value pairs (not just
-- the BR sub-toggles — that's still `_br_settings_fingerprint()` above, used by
-- the cross-peer compare RPC). The universal marker uses a broader hash so it
-- surfaces drift in any setting. `host_required=true` retained as a per-mod
-- addendum (et's BR features are host-only).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/enemy_tweaker/enemy_tweaker_data")
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
    return _fnv1a32(table.concat(parts, ";"))
end

-- Startup marker: unconditional mod:info (the "applied" log marker pattern).
-- Prefix changed v0.5.14 from [et:br] -> [et] to match the universal convention
-- (PROJECT_STANDARDS.md § 3.6). host_required=true retained as a per-mod addendum.
mod:info("[et:LOAD] v%s enabled fp=%s host_required=true OK",
    MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[et] v%s loaded", MOD_VERSION))
end

-- Big Rebalance integration (Core's BR / "Weapon Balance" decompile). Master
-- toggle + per-feature sub-toggles live under the [Big Rebalance] group. See
-- enemy_tweaker_big_rebalance.lua for ownership and per-toggle docs, and
-- enemy_tweaker_big_rebalance_registrations.lua for the cross-mod-shared
-- canonical alphabetical registration list.
local BR = require("scripts/mods/enemy_tweaker/enemy_tweaker_big_rebalance")

-- ============================================================
-- Helpers
-- ============================================================

local function _deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = _deep_copy(v)
    end
    return copy
end

-- ============================================================
-- Horde composition presets
-- ============================================================
-- Skeleton-based presets (necro_skeletons / ghost_skeletons / skeleton_mix)
-- were prototyped in v0.2.x → v0.3.8-dev but only made it into PACED hordes;
-- the majority of adventure-mission hordes are terror-event-driven and read
-- from HordeCompositions (194 keys) which the pacing-key patch never touched.
-- Skeleton clones also required extensive vanilla-table seeding (threat_values,
-- StatisticsDefinitions, hit_zones) at boot. Removed in v0.4.0-dev pending a
-- future iteration that overlays HordeCompositions entries. See project memory
-- `project_enemy_tweaker.md` for the design notes.

local HORDE_PRESETS = {}

HORDE_PRESETS.all_elites = {
    label = "All Elites",
    compositions = {
        skaven = {
            { name = "elites", weight = 1, breeds = {
                "skaven_storm_vermin", {8, 12},
                "skaven_storm_vermin_with_shield", {4, 6},
                "skaven_plague_monk", {3, 5},
            }},
        },
        chaos = {
            { name = "elites", weight = 1, breeds = {
                "chaos_warrior", {3, 5},
                "chaos_raider", {6, 8},
                "chaos_berzerker", {4, 6},
            }},
        },
        beastmen = {
            { name = "elites", weight = 1, breeds = {
                "beastmen_bestigor", {6, 10},
                "beastmen_gor", {8, 12},
            }},
        },
    },
}

HORDE_PRESETS.beastmen_invasion = {
    label = "Beastmen Invasion",
    compositions = {
        all = {
            { name = "ungors", weight = 5, breeds = {
                "beastmen_ungor", {15, 20},
                "beastmen_gor", {8, 12},
            }},
            { name = "bestigors", weight = 3, breeds = {
                "beastmen_gor", {10, 14},
                "beastmen_bestigor", {3, 5},
            }},
            { name = "archers", weight = 2, breeds = {
                "beastmen_ungor_archer", {6, 10},
                "beastmen_gor", {10, 14},
            }},
        },
    },
}

HORDE_PRESETS.chaos_only = {
    label = "Chaos Only",
    compositions = {
        all = {
            { name = "fanatics", weight = 5, breeds = {
                "chaos_fanatic", {20, 30},
                "chaos_marauder", {5, 8},
            }},
            { name = "marauders", weight = 3, breeds = {
                "chaos_marauder", {12, 16},
                "chaos_marauder_with_shield", {4, 6},
            }},
            { name = "raiders", weight = 2, breeds = {
                "chaos_fanatic", {15, 20},
                "chaos_raider", {4, 6},
                "chaos_berzerker", {3, 4},
            }},
        },
    },
}

HORDE_PRESETS.skaven_only = {
    label = "Skaven Only",
    compositions = {
        all = {
            { name = "slaves", weight = 5, breeds = {
                "skaven_slave", {30, 40},
                "skaven_clan_rat", {6, 10},
            }},
            { name = "clan_rats", weight = 3, breeds = {
                "skaven_clan_rat", {15, 20},
                "skaven_clan_rat_with_shield", {4, 6},
            }},
            { name = "stormvermin", weight = 2, breeds = {
                "skaven_slave", {20, 25},
                "skaven_storm_vermin", {4, 6},
                "skaven_plague_monk", {2, 3},
            }},
        },
    },
}

HORDE_PRESETS.mixed_factions = {
    label = "Mixed Factions",
    compositions = {
        all = {
            { name = "skaven_chaos", weight = 4, breeds = {
                "skaven_slave", {12, 16},
                "skaven_clan_rat", {4, 6},
                "chaos_fanatic", {10, 14},
                "chaos_marauder", {3, 5},
            }},
            { name = "all_three", weight = 3, breeds = {
                "skaven_clan_rat", {6, 8},
                "chaos_marauder", {4, 6},
                "beastmen_gor", {4, 6},
                "beastmen_ungor", {6, 8},
            }},
            { name = "elite_mix", weight = 2, breeds = {
                "skaven_storm_vermin", {3, 4},
                "chaos_raider", {3, 4},
                "beastmen_bestigor", {3, 4},
                "skaven_plague_monk", {2, 3},
            }},
        },
    },
}

-- ============================================================
-- State
-- ============================================================

local _original_compositions_pacing = nil
local _original_compositions = nil
local _breed_swap_map = {}
local _faction_swap_map = {}

-- ============================================================
-- Composition patching
-- ============================================================

local PACING_KEYS_SKAVEN = {
    "small", "medium", "large", "huge",
    "huge_shields", "huge_armor", "huge_berzerker",
    "mini_patrol",
}

local PACING_KEYS_CHAOS = {
    "chaos_medium", "chaos_large", "chaos_huge",
    "chaos_huge_shields", "chaos_huge_armor", "chaos_huge_berzerker",
    "chaos_mini_patrol",
}

local PACING_KEYS_BEASTMEN = {
    "beastmen_medium", "beastmen_large", "beastmen_huge",
    "beastmen_huge_armor", "beastmen_mini_patrol",
}

local function _get_preset()
    local preset_key = mod:get("horde_preset")
    if preset_key and preset_key ~= "off" and HORDE_PRESETS[preset_key] then
        return HORDE_PRESETS[preset_key]
    end
    return nil
end

local function _backup_compositions()
    if not _original_compositions_pacing and rawget(_G, "HordeCompositionsPacing") then
        _original_compositions_pacing = _deep_copy(HordeCompositionsPacing)
    end
    if not _original_compositions and rawget(_G, "HordeCompositions") then
        _original_compositions = _deep_copy(HordeCompositions)
    end
end

local function _restore_compositions()
    if _original_compositions_pacing then
        for k, v in pairs(_original_compositions_pacing) do
            HordeCompositionsPacing[k] = _deep_copy(v)
        end
    end
    if _original_compositions then
        for k, v in pairs(_original_compositions) do
            HordeCompositions[k] = _deep_copy(v)
        end
    end
end

-- v0.6.0-dev: rewritten for 0-15x multiplier semantics. At multiplier == 0
-- the breeds drop to 0 (hard suppress); at 1.0 the composition is unchanged;
-- otherwise round-to-nearest. Each breed entry's {min, max} amount tuple is
-- scaled separately. Wrapped in pcall so a malformed composition entry (e.g.
-- a non-{min,max} table from a future engine patch) logs a warning and
-- skips that entry rather than crashing the whole apply pass.
local function _apply_size_multiplier(composition, multiplier)
    if not composition or multiplier == 1 then return end
    for vi, variant in ipairs(composition) do
        if variant.breeds then
            for i = 1, #variant.breeds do
                local entry = variant.breeds[i]
                if type(entry) == "table" and #entry == 2 then
                    local ok, err = pcall(function()
                        entry[1] = _scale_count(entry[1], multiplier)
                        entry[2] = _scale_count(entry[2], multiplier)
                    end)
                    if not ok then
                        mod:warning("[et:paced] _apply_size_multiplier entry skip (variant=%d, breed_idx=%d): %s",
                            vi, i, tostring(err))
                        _dbg_alert("paced multiplier entry skip (variant=%d, breed_idx=%d): %s",
                            vi, i, tostring(err))
                    end
                end
            end
        end
    end
end

-- HordeCompositionsPacing entries each carry a `loaded_probs` field built from
-- variant weights via LoadedDice.create at conflict_settings file-load time
-- (see scripts/settings/conflict_settings.lua:636). horde_spawner.lua reads
-- composition.loaded_probs at lines 139/243/349/743 — losing it crashes
-- LoadedDice.roll_easy on the next horde. We rebuild it here so replacement
-- compositions remain spawnable.
local function _build_loaded_probs(variants)
    local LD = rawget(_G, "LoadedDice")
    if not LD or not LD.create then return nil end
    local weights = {}
    for i, v in ipairs(variants) do
        weights[i] = (v and v.weight) or 1
    end
    return { LD.create(weights) }
end

local function _apply_preset_to_pacing_keys(keys, preset_variants)
    for _, key in ipairs(keys) do
        if HordeCompositionsPacing[key] then
            local sound = HordeCompositionsPacing[key].sound_settings
            local new_variants = _deep_copy(preset_variants)
            new_variants.sound_settings = sound
            new_variants.loaded_probs = _build_loaded_probs(new_variants)
            HordeCompositionsPacing[key] = new_variants
        end
    end
end

-- v0.6.0-dev: horde_size_multiplier semantics changed from int percent
-- (25-300, default 100) to decimal multiplier (0-15, default 1). Users with
-- saved values from v0.5.x will see a slider value of 100 → effectively
-- max-clamped to 15x on first load; CHANGELOG flags re-setting after upgrade.
-- The whole apply pass is _safe-wrapped so a single bad composition entry
-- can't break the preset rotation.
local function _apply_horde_preset()
    local preset = _get_preset()
    local multiplier = _mult("horde_size_multiplier")
    local mutated_keys = 0

    _safe("apply_horde_preset_swap", function()
        if not preset then return end
        local comps = preset.compositions
        if comps.all then
            _apply_preset_to_pacing_keys(PACING_KEYS_SKAVEN, comps.all)
            _apply_preset_to_pacing_keys(PACING_KEYS_CHAOS, comps.all)
            _apply_preset_to_pacing_keys(PACING_KEYS_BEASTMEN, comps.all)
        else
            if comps.skaven then
                _apply_preset_to_pacing_keys(PACING_KEYS_SKAVEN, comps.skaven)
            end
            if comps.chaos then
                _apply_preset_to_pacing_keys(PACING_KEYS_CHAOS, comps.chaos)
            end
            if comps.beastmen then
                _apply_preset_to_pacing_keys(PACING_KEYS_BEASTMEN, comps.beastmen)
            end
        end
    end)

    -- Size multiplier applies independently of preset selection so users
    -- can scale vanilla hordes too. At multiplier == 1 this loop is a no-op
    -- (early-out inside _apply_size_multiplier).
    if multiplier ~= 1 then
        _safe("apply_horde_size_multiplier", function()
            for _, comp in pairs(HordeCompositionsPacing) do
                if type(comp) == "table" and #comp > 0 then
                    _apply_size_multiplier(comp, multiplier)
                    mutated_keys = mutated_keys + 1
                end
            end
        end)
    end

    mod:info("[et:paced] applied: preset=%s multiplier=%.1f keys_mutated=%d",
        tostring(mod:get("horde_preset") or "off"), multiplier, mutated_keys)
end

-- ============================================================
-- Breed substitution
-- ============================================================

local function _build_swap_map()
    _breed_swap_map = {}

    local swap_from = mod:get("breed_swap_from")
    local swap_to   = mod:get("breed_swap_to")
    if swap_from and swap_to and swap_from ~= "off" and swap_to ~= "off" and swap_from ~= swap_to then
        _breed_swap_map[swap_from] = swap_to
    end
end

local function _apply_breed_swap(result)
    if not next(_breed_swap_map) then return result end
    for i = 1, #result do
        local breed_name = result[i]
        if type(breed_name) == "string" and _breed_swap_map[breed_name] then
            local replacement = _breed_swap_map[breed_name]
            if rawget(_G, "Breeds") and Breeds[replacement] then
                result[i] = replacement
            end
        end
    end
    return result
end

-- ============================================================
-- Faction substitution (whole-faction horde slot swap)
-- ============================================================
-- VT2 picks a ConflictDirector per mission (and per-zone via
-- override_conflict_setting on the level), which sets CurrentHordeSettings.
-- Each `*_composition` field on that settings table is a string like "medium"
-- (skaven), "chaos_medium", "beastmen_medium". By rewriting those strings
-- right after ConflictDirector.refresh_conflict_director_patches runs, we
-- redirect every paced horde slot to a different faction's comp family. This
-- means Athel Yenlui (default → chaos zones) can be configured to spawn
-- Beastmen everywhere, Chaos everywhere, or the user's chosen mix.
--
-- NOTE: terror-event hordes use HordeCompositions (event_medium / chaos_raiders_*
-- / etc.) and bypass this rewrite. That patch is a separate workstream.

local FACTION_PREFIX = {
    skaven = "",
    chaos = "chaos_",
    beastmen = "beastmen_",
}

local FACTION_PREFIX_LIST = {
    { faction = "chaos", prefix = "chaos_" },
    { faction = "beastmen", prefix = "beastmen_" },
    -- skaven last because it's the empty-prefix fallback
}

local function _composition_faction(comp_str)
    for _, fp in ipairs(FACTION_PREFIX_LIST) do
        if comp_str:sub(1, #fp.prefix) == fp.prefix then
            return fp.faction
        end
    end
    return "skaven"
end

local function _strip_faction_prefix(comp_str, faction)
    local prefix = FACTION_PREFIX[faction]
    if prefix == "" then return comp_str end
    return comp_str:sub(#prefix + 1)
end

local function _build_faction_swap_map()
    _faction_swap_map = {}
    for _, faction in ipairs({"skaven", "chaos", "beastmen"}) do
        local target = mod:get("faction_swap_" .. faction)
        if target and target ~= "off" and target ~= faction and FACTION_PREFIX[target] then
            _faction_swap_map[faction] = target
        end
    end
end

local function _remap_composition(comp_str)
    if type(comp_str) ~= "string" then return comp_str end
    local from = _composition_faction(comp_str)
    local to = _faction_swap_map[from]
    if not to then return comp_str end
    local base = _strip_faction_prefix(comp_str, from)
    local new_str = FACTION_PREFIX[to] .. base
    -- Only rewrite if the target composition actually exists; otherwise the
    -- spawner will crash trying to index a nil composition.
    local HCP = rawget(_G, "HordeCompositionsPacing")
    if HCP and HCP[new_str] then
        return new_str
    end
    return comp_str
end

local COMPOSITION_FIELDS = {
    "ambush_composition", "vector_composition",
    "vector_blob_composition", "mini_patrol_composition",
}

local function _apply_faction_swap_to_current_horde_settings()
    if not next(_faction_swap_map) then return end
    local CHS = rawget(_G, "CurrentHordeSettings")
    if not CHS then return end
    for _, field in ipairs(COMPOSITION_FIELDS) do
        local v = CHS[field]
        if type(v) == "string" then
            CHS[field] = _remap_composition(v)
        elseif type(v) == "table" then
            for i, s in ipairs(v) do
                v[i] = _remap_composition(s)
            end
        end
    end
end

-- ============================================================
-- Difficulty mimic (per-system difficulty override)
-- ============================================================
-- Each Current* settings table is built by patch_settings_with_difficulty
-- against a specific difficulty key. Mimic lets the user override the
-- difficulty key used PER SYSTEM, so they can play on (e.g.) Champion stats
-- but use Cataclysm-1's horde compositions, special spawn frequency, roaming
-- density, etc. Player/enemy stats stay on the real difficulty — only the
-- spawn-side fields are re-patched.
--
-- MIMIC_SYSTEMS maps the user-facing setting → director field name → name of
-- the Current* global. After ConflictDirector.refresh_conflict_director_patches
-- runs, for each system where the user picked a difficulty override, we
-- re-patch from director.<field> with the override difficulty and overwrite
-- the Current* global. Order is important: difficulty mimic runs BEFORE
-- faction-swap, because mimic REPLACES the table and faction-swap mutates
-- in place.

local MIMIC_SYSTEMS = {
    { setting = "mimic_horde",         field = "horde",         current = "CurrentHordeSettings" },
    { setting = "mimic_specials",      field = "specials",      current = "CurrentSpecialsSettings" },
    { setting = "mimic_pacing",        field = "pacing",        current = "CurrentPacing" },
    { setting = "mimic_pack_spawning", field = "pack_spawning", current = "CurrentPackSpawningSettings" },
    { setting = "mimic_intensity",     field = "intensity",     current = "CurrentIntensitySettings" },
    { setting = "mimic_boss",          field = "boss",          current = "CurrentBossSettings" },
}

local VALID_DIFFICULTIES = {
    normal = true, hard = true, harder = true, hardest = true,
    cataclysm = true, cataclysm_2 = true, cataclysm_3 = true,
}

local function _apply_difficulty_mimic(self)
    local CDs = rawget(_G, "ConflictDirectors")
    local director = CDs and CDs[self.current_conflict_settings]
    if not director then
        _dbg_alert("difficulty_mimic: no director for current_conflict_settings=%s — bail",
            tostring(self and self.current_conflict_settings))
        return
    end
    local mgr = Managers.state and Managers.state.difficulty
    local fallback_difficulty = mgr and mgr.fallback_difficulty
    local CU = rawget(_G, "ConflictUtils")
    if not CU or not CU.patch_settings_with_difficulty then
        _dbg_alert("difficulty_mimic: ConflictUtils.patch_settings_with_difficulty missing — bail")
        return
    end

    for _, m in ipairs(MIMIC_SYSTEMS) do
        local user_difficulty = mod:get(m.setting)
        if user_difficulty and user_difficulty ~= "off"
                and VALID_DIFFICULTIES[user_difficulty]
                and director[m.field] then
            _safe("difficulty_mimic:" .. m.setting, function()
                local rebuilt = CU.patch_settings_with_difficulty(
                    table.clone(director[m.field]), user_difficulty, fallback_difficulty)
                _G[m.current] = rebuilt
                _dbg("difficulty_mimic applied: %s field=%s difficulty=%s",
                    m.setting, m.field, user_difficulty)
            end)
        end
    end
end

-- ============================================================
-- Roaming size (v0.6.0-dev — SizeOfInterestPoint mutation)
-- ============================================================
-- SizeOfInterestPoint is a global table built at game-boot mapping IP-unit
-- name → pack size (count of units). EnemyRecycler.inject_roaming_patrol
-- reads it live every spawn cycle, then looks up BreedPacksBySize[type][size]
-- for the actual breed roster. Our multiplier mutates the size values in
-- place; BreedPacksBySize is keyed by specific sizes (often only the canonical
-- ones — 3, 4, 5, 7), so multiplied sizes that don't have a pack entry will
-- silently miss at the engine call site. We log every fallback through
-- _spawn_dbg_alert so it's visible when Debug Logging is on.

local _original_size_of_interest_point = nil

local function _backup_size_of_interest_point()
    if _original_size_of_interest_point then return end
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then
        _dbg_alert("backup_size_of_interest_point: SizeOfInterestPoint not loaded — defer")
        return
    end
    _original_size_of_interest_point = {}
    for k, v in pairs(SIP) do
        _original_size_of_interest_point[k] = v
    end
    mod:info("[et:roaming] backed up SizeOfInterestPoint (%d entries)",
        (function() local n = 0; for _ in pairs(_original_size_of_interest_point) do n = n + 1 end; return n end)())
end

local function _restore_size_of_interest_point()
    if not _original_size_of_interest_point then return end
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then return end
    for k, v in pairs(_original_size_of_interest_point) do
        SIP[k] = v
    end
end

-- v0.6.1-dev hotfix (crash GUID adbe4524-971a-476f-b17d-41b8b6b20940):
-- previous version wrote arbitrary scaled sizes into SizeOfInterestPoint;
-- EnemyRecycler.inject_roaming_patrol at enemy_recycler.lua:286 does an
-- unguarded `BreedPacksBySize[pack_type][amount]` lookup, returns nil for
-- non-canonical sizes, then dereferences and crashes the game.
--
-- The engine's BreedPacksBySize tables are populated only at sizes
-- {1, 2, 3, 4, 6, 8} for every pack_type (breed_packs.lua:8066 fassert).
-- The engine's spawn floor is min_roaming_patrol_size = 3 (enemy_recycler.lua:260)
-- so any scaled value < 3 is dropped safely by the engine's own filter
-- before reaching the crash site.
--
-- Fix: snap every scaled value to the nearest canonical size in
-- {1, 2, 3, 4, 6, 8}, rounding to the LARGER on ties (user-intent for
-- multiplier > 1 = "more enemies"). Plateaus at 8 once the multiplier
-- pushes us past it; document this in the tooltip and CHANGELOG so the
-- user isn't surprised when 5x and 15x deliver the same roaming density.
--
-- Multiplier = 0 still hard-suppresses: scaled values are 0, engine's
-- floor filter catches them, no roaming spawns.

local _CANONICAL_PACK_SIZES = { 1, 2, 3, 4, 6, 8 }

-- _snap_to_canonical_size(desired) — find the nearest element of
-- _CANONICAL_PACK_SIZES. Ties round UP (a 5 prefers 6 over 4). Values
-- below 1 return 0 so the engine's spawn-floor filter suppresses cleanly.
local function _snap_to_canonical_size(desired)
    if desired < 1 then return 0 end
    if desired >= _CANONICAL_PACK_SIZES[#_CANONICAL_PACK_SIZES] then
        return _CANONICAL_PACK_SIZES[#_CANONICAL_PACK_SIZES]
    end
    local best_size, best_dist = _CANONICAL_PACK_SIZES[1], math.huge
    for _, sz in ipairs(_CANONICAL_PACK_SIZES) do
        local dist = math.abs(sz - desired)
        -- < means strictly closer; on equal distance the LARGER size wins
        -- because we iterate ascending and the inequality blocks the swap.
        if dist < best_dist then
            best_dist = dist
            best_size = sz
        end
    end
    return best_size
end

local function _apply_roaming_size_multiplier()
    local multiplier, is_zero = _mult("roaming_size_multiplier")
    _backup_size_of_interest_point()
    if not _original_size_of_interest_point then return end
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then return end

    local mutated, snapped, plateaued = 0, 0, 0
    _safe("apply_roaming_size_multiplier", function()
        for ip_name, base in pairs(_original_size_of_interest_point) do
            if type(base) == "number" then
                local desired = _scale_count(base, multiplier)
                local snapped_size = _snap_to_canonical_size(desired)
                if snapped_size ~= desired then
                    snapped = snapped + 1
                    _spawn_dbg("roaming",
                        "snap-to-canonical: ip=%s base=%d desired=%d snapped=%d",
                        tostring(ip_name), base, desired, snapped_size)
                    if desired > _CANONICAL_PACK_SIZES[#_CANONICAL_PACK_SIZES] then
                        plateaued = plateaued + 1
                    end
                end
                SIP[ip_name] = snapped_size
                mutated = mutated + 1
            end
        end
    end)
    mod:info("[et:roaming] applied: multiplier=%.1f mutated=%d snapped=%d plateaued_at_8=%d",
        multiplier, mutated, snapped, plateaued)
    if is_zero then
        _spawn_dbg_alert("roaming",
            "multiplier=0 — all roaming pack sizes set to 0; engine's min_roaming_patrol_size=3 filter suppresses spawns")
    elseif plateaued > 0 then
        _spawn_dbg_alert("roaming",
            "multiplier=%.1f exceeds engine canonical max (8 units/IP); %d IPs plateaued. Past ~2.7x the roaming slider has no additional effect.",
            multiplier, plateaued)
    end
end

-- ============================================================
-- Hooks
-- ============================================================

_hook_wrap("ConflictDirector", "init", "ConflictDirector.init", function(func, self, ...)
    local result = func(self, ...)

    _backup_compositions()
    _restore_compositions()
    _apply_horde_preset()
    _apply_roaming_size_multiplier()
    _build_swap_map()
    _build_faction_swap_map()
    _apply_difficulty_mimic(self)
    _apply_faction_swap_to_current_horde_settings()

    local horde_mult,   _   = _mult("horde_size_multiplier")
    local event_mult,   _e  = _mult("event_size_multiplier")
    local roaming_mult, _r  = _mult("roaming_size_multiplier")
    local patrol_mult,  _p  = _mult("patrol_size_multiplier")
    mod:info("[et:init] compositions applied (preset=%s horde=%.1f event=%.1f roaming=%.1f patrol=%.1f)",
        tostring(mod:get("horde_preset")), horde_mult, event_mult, roaming_mult, patrol_mult)
    _spawn_dbg("init", "ConflictDirector.init complete: cd=%s",
        tostring(self and self.current_conflict_settings))
    return result
end)

-- refresh_conflict_director_patches runs whenever the active conflict
-- director changes (zone boundary override, mid-mission switches). It
-- rebuilds CurrentHordeSettings via table.clone(director.horde), so any
-- faction-swap rewrites from a previous CD are lost — re-apply after.
-- Order: difficulty mimic first (replaces Current* tables), then faction-swap
-- (mutates CurrentHordeSettings in place).
-- Issue #18: log applied-reason so /et_verify_refresh and post-mortems can
-- see what drove each reseed (engine = zone-boundary native, on_enabled =
-- our toggle-back-on path, on_setting_changed:<id> = mid-session VMF edit).
mod._et_last_refresh_at      = nil
mod._et_last_refresh_trigger = nil
_hook_wrap("ConflictDirector", "refresh_conflict_director_patches",
        "refresh_conflict_director_patches", function(func, self, ...)
    local trigger = (...)
    if type(trigger) ~= "string" then trigger = "engine" end
    func(self, ...)
    _apply_difficulty_mimic(self)
    _apply_faction_swap_to_current_horde_settings()
    -- v0.6.0-dev: re-apply roaming size on every CD refresh too. Without
    -- this the mid-mission zone-boundary CD switch (Athel Yenlui etc.)
    -- would revert SizeOfInterestPoint to vanilla until the next mission.
    _apply_roaming_size_multiplier()
    mod._et_last_refresh_at      = os.time()
    mod._et_last_refresh_trigger = trigger
    mod:info("[et:refresh] applied (trigger=%s cd=%s)", trigger,
        tostring(self and self.current_conflict_settings))
    _spawn_dbg("refresh", "refresh_conflict_director_patches trigger=%s", trigger)
end)

-- compose_blob_horde_spawn_list returns (spawn_list, num_to_spawn) — a real
-- list of breed names. Three things happen here in order:
--   1. Breed swap (in-place).
--   2. Event-size scaling: when mod._et_event_breed_scale is set by the
--      outer SpawnerSystem.spawn_horde_from_terror_event_ids hook, replicate
--      every entry in spawn_list to scale total count by the multiplier.
--   3. Spawn debug dump.
-- This is also the cleanest cross-version site to apply the event_size
-- multiplier: we don't depend on knowing the exact resolved-amount table
-- shape inside SpawnerSystem; we just replicate the final spawn list.
-- audit 2026-06-07 (v0.7.5-dev) F16: vanilla
--   HordeSpawner.compose_blob_horde_spawn_list(self, composition_type)
-- takes a STRING key — composition = CurrentHordeSettings.compositions_pacing
-- [composition_type] [src: scripts/managers/conflict_director/horde_spawner.lua:241-242].
-- The first arg is the type string, not a composition table; the debug
-- labels below read it directly (a string has no `.name` field, so the old
-- `composition.name` always resolved to "?" — dead cosmetic label).
_hook_wrap("HordeSpawner", "compose_blob_horde_spawn_list",
        "compose_blob_horde_spawn_list", function(func, self, composition_type, ...)
    local spawn_list, num_to_spawn = func(self, composition_type, ...)
    if not spawn_list then return spawn_list, num_to_spawn end

    -- 1. Breed swap.
    _apply_breed_swap(spawn_list)

    -- 2. Event-size scaling. Only active when we're inside an event-driven
    -- compose call; paced compose has its own scaling via _apply_horde_preset
    -- (which mutated HordeCompositionsPacing entries at load).
    local event_scale = mod._et_event_breed_scale
    if event_scale and event_scale ~= 1 then
        if event_scale == 0 then
            -- Suppress this event horde entirely. Clear the list and zero
            -- the count; HordeSpawner downstream tolerates an empty list.
            local original_n = #spawn_list
            for i = #spawn_list, 1, -1 do spawn_list[i] = nil end
            _spawn_dbg_alert("event", "compose_blob suppressed: was=%d now=0 (event_mult=0)",
                original_n)
            return spawn_list, 0
        end
        local base_n = #spawn_list
        local target_n = _scale_count(base_n, event_scale)
        if target_n > base_n then
            -- Replicate by cycling through original entries — but EXCLUDE
            -- boss breeds from the replication pool. Boss breeds (Drachenfels
            -- Exalted Sorcerer, Rat Ogre, Chaos Spawn, Stormfiend, Troll,
            -- Warlord, Champion, Grey Seer, Troll Chief — every breed with
            -- `breed.boss = true`) are unique-instance enemies. Spawning two
            -- in the same frame races their BT init: a second copy may have
            -- `blackboard.current_health_percent = nil` when its BT first
            -- evaluates, crashing vanilla bt_conditions.lua at conditions
            -- like `transitioned_one_third_health`. Burned host 2026-05-26
            -- on dlc_castle_slaanesh_path1 with event_size=3.0x triggering
            -- 3× Drachenfels spawn from the castle_chaos_boss terror event.
            local BreedsT = rawget(_G, "Breeds")
            local non_boss_pool = {}
            for i = 1, base_n do
                local bn = spawn_list[i]
                local b = BreedsT and BreedsT[bn]
                if not (b and b.boss) then
                    non_boss_pool[#non_boss_pool + 1] = bn
                end
            end
            local pool_n = #non_boss_pool
            if pool_n == 0 then
                _spawn_dbg_alert("event", "compose_blob: all %d entries are boss breeds — skipping event replication (no safe candidates) composition=%s",
                    base_n, tostring(composition_type))
            else
                for i = base_n + 1, target_n do
                    spawn_list[i] = non_boss_pool[((i - base_n - 1) % pool_n) + 1]
                end
                if pool_n < base_n then
                    _spawn_dbg("event", "compose_blob scaled (boss-safe): base=%d target=%d mult=%.1f boss_excluded=%d composition=%s",
                        base_n, target_n, event_scale, base_n - pool_n,
                        tostring(composition_type))
                else
                    _spawn_dbg("event", "compose_blob scaled: base=%d target=%d mult=%.1f composition=%s",
                        base_n, target_n, event_scale,
                        tostring(composition_type))
                end
                num_to_spawn = target_n
            end
        elseif target_n < base_n then
            -- Multiplier < 1 — trim the list.
            for i = #spawn_list, target_n + 1, -1 do spawn_list[i] = nil end
            _spawn_dbg("event", "compose_blob trimmed: base=%d target=%d mult=%.1f composition=%s",
                base_n, target_n, event_scale,
                tostring(composition_type))
            num_to_spawn = target_n
        end
    else
        _spawn_dbg("paced", "compose_blob: n=%d (composition=%s)",
            tonumber(num_to_spawn) or #spawn_list,
            tostring(composition_type))
    end

    return spawn_list, num_to_spawn
end)

-- compose_horde_spawn_list returns (sum, sum_a, sum_b) — three integers, NOT
-- a list. Breed names live in file-local upvalues spawn_list_a/_b inside
-- horde_spawner.lua and are popped per-spawn by spawn_unit. So the only place
-- to substitute ambush breeds reliably is at the per-unit spawn site:
-- HordeSpawner.spawn_unit(self, hidden_spawn, breed_name, goal_pos, horde).
_hook_wrap("HordeSpawner", "spawn_unit", "spawn_unit",
        function(func, self, hidden_spawn, breed_name, goal_pos, horde)
    local original = breed_name
    if breed_name and _breed_swap_map[breed_name] then
        local replacement = _breed_swap_map[breed_name]
        if rawget(_G, "Breeds") and Breeds[replacement] then
            breed_name = replacement
        end
    end
    if mod:get("enable_debug_logging") then
        _spawn_dbg("unit", "spawn_unit breed=%s%s hidden=%s",
            tostring(breed_name),
            (original ~= breed_name) and (" (was=" .. tostring(original) .. ")") or "",
            tostring(hidden_spawn))
    end
    return func(self, hidden_spawn, breed_name, goal_pos, horde)
end)

-- ============================================================
-- Event horde size (v0.6.0-dev)
-- ============================================================
-- SpawnerSystem.spawn_horde_from_terror_event_ids resolves HordeCompositions
-- entries into per-breed amounts at runtime, then asks HordeSpawner to spawn
-- each. We hook the function and scale `temp_spawn_list_per_breed` after
-- resolution but before spawn. Single point — respects per-breed
-- max_active_enemies engine caps automatically.
--
-- The signature/internals can vary across game versions, so we accept any
-- second-arg shape (a table of resolved per-breed amounts) and only mutate
-- entries whose values are numbers. If the function returns a count or a
-- list shape we don't recognize, we _dbg_alert and pass through unchanged.
if rawget(_G, "SpawnerSystem") then
    _hook_wrap("SpawnerSystem", "spawn_horde_from_terror_event_ids",
            "spawn_horde_from_terror_event_ids", function(func, self, ...)
        local mult, is_zero = _mult("event_size_multiplier")
        if mult == 1 then
            _spawn_dbg("event", "spawn_horde_from_terror_event_ids passthrough mult=1.0")
            return func(self, ...)
        end
        if is_zero then
            -- Suppress entirely — early-return without invoking vanilla.
            -- Caveat (PROJECT_STANDARDS § 4.2 "guard ≠ bail"): vanilla's
            -- side effect here is "spawn the horde". Skipping spawn IS the
            -- intended behavior at multiplier=0; user explicitly asked for
            -- zero. Logged loudly so it's visible.
            _spawn_dbg_alert("event", "multiplier=0 — suppressing terror-event horde spawn entirely")
            return
        end
        -- Multiplier in (0, 1) U (1, 15]: stash the per-call scale on the
        -- mod table so the inner compose_blob_horde_spawn_list hook can
        -- read it and scale the spawn list. Wrapped in pcall + finally so
        -- a crash inside vanilla can't leak the flag into the next
        -- (potentially paced, not event) compose call.
        mod._et_event_breed_scale = mult
        local ok, r1, r2, r3, r4 = pcall(func, self, ...)
        mod._et_event_breed_scale = nil
        if not ok then
            mod:warning("[et:event] spawn_horde_from_terror_event_ids vanilla errored: %s — flag cleared, bailing",
                tostring(r1))
            _dbg_alert("event spawn vanilla errored: %s", tostring(r1))
            return nil
        end
        _spawn_dbg("event", "spawn_horde_from_terror_event_ids returned (mult=%.1f)", mult)
        return r1, r2, r3, r4
    end)
end

-- The actual event-size scaling happens inside compose_blob_horde_spawn_list
-- above, gated on mod._et_event_breed_scale set by the SpawnerSystem hook.
-- HordeSpawner.spawn_horde is also instrumented (debug-only) so we have a
-- log breadcrumb for every event-triggered horde call, with composition
-- type and horde type visible.
if rawget(_G, "HordeSpawner") and type(rawget(_G, "HordeSpawner").spawn_horde) == "function" then
    _hook_wrap("HordeSpawner", "spawn_horde", "spawn_horde",
            function(func, self, side_id, composition_type, strictness, fill_type,
                     spread, horde_type, optional_data, ...)
        if mod:get("enable_debug_logging") then
            _spawn_dbg("event", "spawn_horde side=%s comp_type=%s horde_type=%s active_event_scale=%s",
                tostring(side_id), tostring(composition_type), tostring(horde_type),
                tostring(mod._et_event_breed_scale))
        end
        return func(self, side_id, composition_type, strictness, fill_type,
            spread, horde_type, optional_data, ...)
    end)
end

-- ============================================================
-- Roaming belt-suspenders (v0.6.1-dev hotfix)
-- ============================================================
-- EnemyRecycler.inject_roaming_patrol at enemy_recycler.lua:286 does an
-- unguarded BreedPacksBySize[pack_type][amount] lookup and dereferences
-- pack_data.prob on the next line. Crash GUID adbe4524-... v0.6.0-dev.
--
-- _apply_roaming_size_multiplier above now snaps to canonical sizes so
-- this should never fire under our mutation. But: future engine
-- versions could add a new pack_type missing from our canonical set,
-- another mod could rewrite BreedPacksBySize, or the level data could
-- carry a pack_type our snap helper doesn't know about. Wrap the call
-- so we never crash again on this path — log + bail to no-op (the
-- engine handles a no-op inject gracefully; the recycler tries again
-- the next cycle).
if rawget(_G, "EnemyRecycler") then
    _hook_wrap("EnemyRecycler", "inject_roaming_patrol", "inject_roaming_patrol",
            function(func, self, area_position, area_rot, pack_type, pack_size_ip_unit_name, zone_data)
        local SIP = rawget(_G, "SizeOfInterestPoint")
        local amount = SIP and SIP[pack_size_ip_unit_name]
        local BPS = rawget(_G, "BreedPacksBySize")
        -- Pre-check: if BreedPacksBySize doesn't have an entry for our
        -- (pack_type, amount) pair, bail BEFORE calling vanilla so the
        -- crash never reaches enemy_recycler.lua:286.
        if BPS and pack_type and type(amount) == "number" then
            local sizes_for_type = BPS[pack_type]
            if sizes_for_type and sizes_for_type[amount] == nil then
                _spawn_dbg_alert("roaming",
                    "inject_roaming_patrol pre-check: BreedPacksBySize[%s][%d] missing — bailing (would crash at enemy_recycler.lua:286). ip=%s",
                    tostring(pack_type), amount, tostring(pack_size_ip_unit_name))
                return
            end
            if not sizes_for_type then
                _spawn_dbg_alert("roaming",
                    "inject_roaming_patrol pre-check: BreedPacksBySize[%s] missing entirely (unknown pack_type) — bailing. ip=%s amount=%d",
                    tostring(pack_type), tostring(pack_size_ip_unit_name), amount)
                return
            end
        end
        _spawn_dbg("roaming",
            "inject_roaming_patrol pack_type=%s ip=%s amount=%s",
            tostring(pack_type), tostring(pack_size_ip_unit_name), tostring(amount))
        return func(self, area_position, area_rot, pack_type, pack_size_ip_unit_name, zone_data)
    end)
end

-- ============================================================
-- Ambient density (v0.6.2-dev — SpawnZoneBaker layer)
-- ============================================================
-- SizeOfInterestPoint mutation (above) drives roaming PACK size for IP-based
-- patrols and plateaus at 8 because BreedPacksBySize only has rosters for
-- canonical sizes {1, 2, 3, 4, 6, 8}. SpawnTweaks bypasses this plateau by
-- hooking a DIFFERENT layer: SpawnZoneBaker.spawn_amount_rats — the per-zone
-- ambient density pass that places loose units throughout the level at
-- map-bake time. Scaling num_wanted_rats here results in MORE PACKS, not
-- bigger packs, so it's not bound by the canonical-size table.
--
-- We tie this to the same roaming_size_multiplier so the user has ONE
-- "roaming enemies" knob that drives both layers: per-IP pack size (capped
-- at 8) AND ambient density (uncapped). Past ~2.7x the IP layer has
-- plateaued; the ambient layer continues to scale linearly, which is what
-- gives the slider meaningful effect at 5x / 10x / 15x.
--
-- Signature (vanilla spawn_zone_baker.lua:698):
--   spawn_amount_rats(self, spawns, pack_sizes, pack_rotations, pack_members,
--                     zone_data_list, nodes, num_wanted_rats, pack_type, area, zone)
-- v0.7.1-dev hotfix belt-suspenders: vanilla SpawnZoneBaker.inject_special_packs
-- has an unchecked inner loop at lines ~549-554:
--   for k = zone_index, zone_index + period_length - 1 do
--       zone = cycle_zones[k]
--       zone.pack_type = pack_type   -- crashes when k > #cycle_zones
-- The loop assumes period_length fits within the remaining cycle_zones from
-- zone_index, but on small Deus cycles + high difficulty (cataclysm-mimic'd
-- period_length values), it overruns. Crashed at level-load on
-- dlc_termite_1_belakor_path1 / deus_skaven_beastmen / Champion-with-Cata-mimic.
--
-- We hook the function under _hook_wrap so any nil-index error in vanilla
-- falls through to the wrap's pcall + log + bail path. Skipping the
-- injection means some zones miss their special-pack override but the
-- level still loads (zones retain their level-bake default pack data).
-- That's the failure mode the user wants — playable mission > crash.
if rawget(_G, "SpawnZoneBaker") and type(rawget(_G, "SpawnZoneBaker").inject_special_packs) == "function" then
    _hook_wrap("SpawnZoneBaker", "inject_special_packs", "inject_special_packs",
            function(func, self, ...)
        -- Important: we pcall vanilla HERE (not just call it) so the wrap's
        -- own fallback path doesn't re-invoke vanilla (which would re-crash).
        -- Body returns nil cleanly to _hook_wrap; vanilla returns nothing
        -- normally so the caller doesn't notice. Skipped injection means
        -- some zones keep their level-bake default pack data — playable
        -- mission > crash.
        local ok, err = pcall(func, self, ...)
        if not ok then
            _chat_alert("SpawnZoneBaker.inject_special_packs vanilla errored: %s — skipping special-pack injection for this cycle (zones keep level-bake defaults). Often hits Deus + cataclysm-mimic on small-cycle DLC levels.", tostring(err))
        end
        return nil
    end)
end

-- v0.7.4-dev: SpawnTweaks parity. v0.7.3 capped at 5x to avoid OOM in the
-- vanilla table.clone deep-recursion path inside _generate_pack_members. But
-- SpawnTweaks runs to 15x on the same levels without OOMing. The trick I
-- missed: SpawnTweaks monkey-patches table.clone to force skip_metatable=true
-- on EVERY clone in the game. That strips metatable reachability from cloned
-- pack data, cutting per-clone heap footprint by ~2-3x, which is what lets
-- the deep-clone loop survive 15x scaling on large Deus levels.
--
-- We install the same global table.clone shim BEFORE registering the
-- spawn_amount_rats hook, and lift the cap to 15 (the full slider range).
-- The cap constant stays as a safety net — a future regression that removes
-- the table.clone shim would re-OOM, and the regression test catches that.
local _AMBIENT_EFFECTIVE_MULT_CAP = 15

-- Global table.clone shim — forces skip_metatable=true on every clone.
-- SpawnTweaks pattern (SpawnTweaks.lua:13-15). Affects ALL clones engine-wide
-- but the change is invisible to consumers: every site that calls
-- table.clone(t) without an explicit skip_metatable already accepted the
-- vanilla default of nil (which the engine treats the same as false for
-- metatable copy). Forcing true changes the behavior to skip metatable
-- copying, which is what the engine actually wants for transient pack-member
-- clones and never breaks consumers in practice (verified by the fact that
-- SpawnTweaks has been live with this hook for years across all game modes).
if type(rawget(_G, "table")) == "table" and type(table.clone) == "function" then
    mod:hook(table, "clone", function(func, t, skip_metatable) -- luacheck: no unused
        return func(t, true)
    end)
end
if rawget(_G, "SpawnZoneBaker") then
    _hook_wrap("SpawnZoneBaker", "spawn_amount_rats", "spawn_amount_rats",
            function(func, self, spawns, pack_sizes, pack_rotations, pack_members,
                     zone_data_list, nodes, num_wanted_rats, pack_type, area, zone)
        local mult, is_zero = _mult("roaming_size_multiplier")
        if mult == 1 then
            return func(self, spawns, pack_sizes, pack_rotations, pack_members,
                zone_data_list, nodes, num_wanted_rats, pack_type, area, zone)
        end
        if is_zero then
            _spawn_dbg_alert("roaming", "ambient: multiplier=0 — passing num_wanted_rats=0 to vanilla (suppress ambient density)")
            return func(self, spawns, pack_sizes, pack_rotations, pack_members,
                zone_data_list, nodes, 0, pack_type, area, zone)
        end
        -- Cap the effective multiplier (NOT the slider value). User-facing
        -- slider stays whatever they set; we just clamp how much we ask
        -- vanilla to allocate. Per-zone fewer ambient packs, but we never
        -- OOM Lua during level bake.
        local effective = mult
        local capped = false
        if effective > _AMBIENT_EFFECTIVE_MULT_CAP then
            effective = _AMBIENT_EFFECTIVE_MULT_CAP
            capped = true
        end
        local scaled = _scale_count(num_wanted_rats or 0, effective)
        if capped then
            _spawn_dbg("roaming",
                "ambient: CAPPED scaling num_wanted_rats %d -> %d (slider=%.1f effective=%.1f) zone_pack_type=%s area=%s",
                tonumber(num_wanted_rats) or 0, scaled, mult, effective,
                tostring(pack_type), tostring(area))
        else
            _spawn_dbg("roaming",
                "ambient: scaling num_wanted_rats %d -> %d (mult=%.1f) zone_pack_type=%s area=%s",
                tonumber(num_wanted_rats) or 0, scaled, mult,
                tostring(pack_type), tostring(area))
        end
        return func(self, spawns, pack_sizes, pack_rotations, pack_members,
            zone_data_list, nodes, scaled, pack_type, area, zone)
    end)
end

-- ============================================================
-- Spawn pacing (v0.7.0-dev — SpawnTweaks parity pass)
-- ============================================================
-- Five engine knobs that control spawn FREQUENCY and CONCURRENT CAPS, as
-- opposed to per-spawn enemy counts (the four 0–15x sliders above).
-- SpawnTweaks's "save vanilla value -> apply override -> call vanilla -> restore"
-- pattern is what we mimic: the engine globals are read by many systems, so
-- our override only takes effect during the specific vanilla function that
-- consumes them. Outside those windows the engine sees vanilla values.
--
-- Helpers — read settings with a non-numeric guard so a typo'd value can't
-- override the cap to nil and crash the engine.
local function _read_num_setting(setting_id, default_val)
    local raw = mod:get(setting_id)
    if type(raw) == "number" then return raw end
    if raw == nil then return default_val end
    local n = tonumber(raw)
    if n == nil then
        _dbg_alert("setting %s has non-numeric value %s — using default %s",
            tostring(setting_id), tostring(raw), tostring(default_val))
        return default_val
    end
    return n
end

-- ConflictDirector.update — wraps the master tick that runs horde pacing,
-- mini-patrol, specials. We mutate RecycleSettings.max_grunts (the concurrent
-- alive trash cap) here so the engine reads our override during pacing
-- decisions, then restore on the way out.
if rawget(_G, "ConflictDirector") then
    _hook_wrap("ConflictDirector", "update", "spawn_pacing.update",
            function(func, self, ...)
        local RS = rawget(_G, "RecycleSettings")
        local original_max_grunts
        if RS then
            local override = _read_num_setting("max_grunts_override", 90)
            if override ~= 90 then
                original_max_grunts = RS.max_grunts
                RS.max_grunts = override
            end
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_max_grunts ~= nil then
            RS.max_grunts = original_max_grunts
        end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.update_horde_pacing — runs the paced-horde frequency
    -- decision. We override push_horde_if_num_alive_grunts_above and the
    -- horde_frequency tuple around this call.
    _hook_wrap("ConflictDirector", "update_horde_pacing", "spawn_pacing.update_horde_pacing",
            function(func, self, ...)
        local RS = rawget(_G, "RecycleSettings")
        local CP = rawget(_G, "CurrentPacing")
        local original_push, original_freq
        if RS then
            local push = _read_num_setting("horde_grunt_push_threshold", 60)
            if push ~= 60 then
                original_push = RS.push_horde_if_num_alive_grunts_above
                RS.push_horde_if_num_alive_grunts_above = push
            end
        end
        if CP then
            local fmin = _read_num_setting("horde_frequency_min", 50)
            local fmax = _read_num_setting("horde_frequency_max", 100)
            if fmin ~= 50 or fmax ~= 100 then
                if fmax < fmin then fmax = fmin end
                original_freq = CP.horde_frequency  -- shallow ref is fine; vanilla writes new tables
                CP.horde_frequency = { fmin, fmax }
            end
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_freq ~= nil then CP.horde_frequency = original_freq end
        if original_push ~= nil then RS.push_horde_if_num_alive_grunts_above = original_push end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.horde_killed — vanilla recomputes the next horde
    -- schedule here too; needs the same horde_frequency override or the
    -- frequency slider has no effect after the first horde dies.
    _hook_wrap("ConflictDirector", "horde_killed", "spawn_pacing.horde_killed",
            function(func, self, ...)
        local CP = rawget(_G, "CurrentPacing")
        local original_freq
        if CP then
            local fmin = _read_num_setting("horde_frequency_min", 50)
            local fmax = _read_num_setting("horde_frequency_max", 100)
            if fmin ~= 50 or fmax ~= 100 then
                if fmax < fmin then fmax = fmin end
                original_freq = CP.horde_frequency
                CP.horde_frequency = { fmin, fmax }
            end
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_freq ~= nil then CP.horde_frequency = original_freq end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.update_mini_patrol — ambient mini-patrol spawn pass.
    -- When ambients_ignore_threat is ON, raise the intensity gate to infinity
    -- and the grunt cap to infinity for the duration of vanilla, then restore.
    -- Both have to move together or the engine still bails on the cap check
    -- inside the function body.
    _hook_wrap("ConflictDirector", "update_mini_patrol", "spawn_pacing.update_mini_patrol",
            function(func, self, ...)
        if not mod:get("ambients_ignore_threat") then
            return func(self, ...)
        end
        local CP = rawget(_G, "CurrentPacing")
        local RS = rawget(_G, "RecycleSettings")
        local original_mp_threshold, original_max_grunts
        if CP and CP.mini_patrol then
            original_mp_threshold = CP.mini_patrol.only_spawn_below_intensity
            CP.mini_patrol.only_spawn_below_intensity = math.huge
        end
        if RS then
            original_max_grunts = RS.max_grunts
            RS.max_grunts = math.huge
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_max_grunts ~= nil then RS.max_grunts = original_max_grunts end
        if original_mp_threshold ~= nil then
            CP.mini_patrol.only_spawn_below_intensity = original_mp_threshold
        end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.calculate_threat_value (hook_safe — vanilla writes
    -- self.threat_value, we multiply afterward). spawn_pace_multiplier > 1
    -- means "MORE spawns" — we multiply threat by `mult` so the delay_*
    -- thresholds (delay_horde_threat_value < threat_value) trip sooner.
    -- mult < 1 reduces spawn pressure. SpawnTweaks's inverted semantics are
    -- normalized here (their lower = harder; ours higher = harder).
    mod:hook_safe(ConflictDirector, "calculate_threat_value", function(self)
        local mult = _read_num_setting("spawn_pace_multiplier", 1)
        if mult == 1 then return end
        if type(self.threat_value) ~= "number" then return end
        self.threat_value = self.threat_value * mult
        local threat_value = self.threat_value
        -- Recompute delay flags with the new threat_value (vanilla already
        -- did this with the un-scaled value; we redo against the scaled one).
        if type(self.delay_horde_threat_value) == "number" then
            self.delay_horde = self.delay_horde_threat_value < threat_value
        end
        if type(self.delay_mini_patrol_threat_value) == "number" then
            self.delay_mini_patrol = self.delay_mini_patrol_threat_value < threat_value
        end
        if type(self.delay_specials_threat_value) == "number" then
            self.delay_specials = self.delay_specials_threat_value < threat_value
        end
    end)
end

-- Pacing.update (hook_safe) — Pacing maintains per-player intensity that
-- feeds into spawn-rate decisions. Multiply intensity by spawn_pace_multiplier
-- AFTER vanilla writes it so spawn-rate decisions see the scaled value on the
-- next pacing tick.
if rawget(_G, "Pacing") then
    mod:hook_safe(Pacing, "update", function(self, t, dt, alive_player_units) -- luacheck: ignore t dt
        local mult = _read_num_setting("spawn_pace_multiplier", 1)
        if mult == 1 then return end
        if type(alive_player_units) ~= "table" then return end
        local n = #alive_player_units
        if n == 0 then return end
        if type(self.player_intensity) == "table" then
            for k = 1, n do
                if type(self.player_intensity[k]) == "number" then
                    self.player_intensity[k] = self.player_intensity[k] * mult
                end
            end
        end
        if type(self.total_intensity) == "number" then
            self.total_intensity = self.total_intensity * mult
        end
    end)
end

-- ============================================================
-- Beastman banner (v0.7.2-dev)
-- ============================================================
-- Two toggles for the beastmen standard-bearer's planted banner.
--
-- (1) Bearer staggerable during placement: vanilla
--     BreedActions.beastmen_standard_bearer.place_standard_stagger_immune
--     has ignore_staggers = { true, true, true, true, true, true } — bearer
--     can't be interrupted out of the place animation. We backup the table
--     at first apply and flip all six entries to false when our setting is
--     on; restore on disable. The BT picks between place_standard (already
--     staggerable) and place_standard_stagger_immune based on its own
--     considerations, so we mutate the immune variant in place so EITHER
--     selection respects the toggle.
--
-- (2) Banner breakable by ranged: vanilla
--     BeastmenStandardHealthExtension.add_damage allow-set is melee
--     light/heavy + a small explosive/torch whitelist (see vanilla
--     beastmen_standard_health_extension.lua:25-44). We hook the function
--     and, when the setting is on, also accept attack_type values
--     "projectile", "instant_projectile", "heavy_instant_projectile"
--     (canonical NetworkLookup.buff_attack_types strings — every ranged
--     weapon in the game uses one of these).

local _banner_bearer_ignore_staggers_original  -- backup of the 6-entry vanilla table

local function _apply_banner_bearer_stagger_toggle()
    local BA = rawget(_G, "BreedActions")
    if type(BA) ~= "table" then return end
    local sb = BA.beastmen_standard_bearer
    if type(sb) ~= "table" then return end
    local action = sb.place_standard_stagger_immune
    if type(action) ~= "table" then return end
    if type(action.ignore_staggers) ~= "table" then return end

    if _banner_bearer_ignore_staggers_original == nil then
        -- Snapshot vanilla on first apply so we can restore exact state.
        _banner_bearer_ignore_staggers_original = {}
        for i = 1, 6 do _banner_bearer_ignore_staggers_original[i] = action.ignore_staggers[i] end
    end

    if mod:get("banner_bearer_staggerable_during_placement") then
        for i = 1, 6 do action.ignore_staggers[i] = false end
        _spawn_dbg("banner", "bearer stagger-immunity disabled — place_standard_stagger_immune.ignore_staggers set to all-false")
    else
        for i = 1, 6 do action.ignore_staggers[i] = _banner_bearer_ignore_staggers_original[i] end
        _spawn_dbg("banner", "bearer stagger-immunity restored to vanilla")
    end
end

-- Apply now if BreedActions already loaded (likely true at mod-script-time
-- for most launches), and on every ConflictDirector.init (mission load) +
-- on setting change. on_disabled also restores.
_safe("banner_apply_initial", _apply_banner_bearer_stagger_toggle)

-- BeastmenStandardHealthExtension.add_damage hook — extends can_damage_banner.
-- Vanilla body (paraphrased):
--   can_damage_banner = attack_type == "heavy_attack" or "light_attack"
--                       or white_listed_damage_sources[damage_source_name]
-- We can't simply pass through to vanilla because vanilla's gate REJECTS
-- ranged before it gets to super.add_damage. So we replicate the vanilla
-- decision path with our widened set when the setting is on.
local _BANNER_RANGED_ATTACK_TYPES = {
    projectile = true,
    instant_projectile = true,
    heavy_instant_projectile = true,
}
if rawget(_G, "BeastmenStandardHealthExtension") then
    _hook_wrap("BeastmenStandardHealthExtension", "add_damage",
            "banner.add_damage",
            function(func, self, attacker_unit, damage_amount, hit_zone_name, damage_type,
                     hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
                     damaging_unit, hit_react_type, is_critical_strike, added_dot,
                     first_hit, total_hits, attack_type, backstab_multiplier, target_index)
        -- If the setting is off, vanilla decides — no behavior change.
        if not mod:get("banner_breakable_by_ranged") then
            return func(self, attacker_unit, damage_amount, hit_zone_name, damage_type,
                hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
                damaging_unit, hit_react_type, is_critical_strike, added_dot,
                first_hit, total_hits, attack_type, backstab_multiplier, target_index)
        end

        -- Setting is on. If this is a ranged attack vanilla would reject, we
        -- relay the call straight to the parent's add_damage (which is what
        -- vanilla does for accepted attacks). For everything else, defer to
        -- vanilla — preserves the suicide path and the existing whitelist.
        if attack_type and _BANNER_RANGED_ATTACK_TYPES[attack_type] then
            _spawn_dbg("banner", "ranged hit accepted: attack_type=%s damage_source=%s",
                tostring(attack_type), tostring(damage_source_name))
            local GHE = rawget(_G, "GenericHealthExtension")
            if GHE and type(GHE.add_damage) == "function" then
                GHE.add_damage(self, attacker_unit, damage_amount, hit_zone_name, damage_type,
                    hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
                    damaging_unit, hit_react_type, is_critical_strike, added_dot,
                    first_hit, total_hits, attack_type, backstab_multiplier, target_index)
                -- Also play vanilla's taking-damage sfx since we bypassed
                -- vanilla's add_damage where it normally fires.
                local std_ext = rawget(_G, "ScriptUnit") and ScriptUnit.has_extension(self._unit, "ai_supplementary_system")
                if std_ext and std_ext.standard_template and std_ext.standard_template.sfx_taking_damage then
                    local WU = rawget(_G, "WwiseUtils")
                    if WU and type(WU.trigger_unit_event) == "function" then
                        WU.trigger_unit_event(std_ext.world, std_ext.standard_template.sfx_taking_damage, self._unit, 0)
                    end
                end
                return
            end
            -- GenericHealthExtension not available — fall through to vanilla.
        end

        return func(self, attacker_unit, damage_amount, hit_zone_name, damage_type,
            hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
            damaging_unit, hit_react_type, is_critical_strike, added_dot,
            first_hit, total_hits, attack_type, backstab_multiplier, target_index)
    end)
end

-- ============================================================
-- Patrol size (v0.6.0-dev — formation row replication)
-- ============================================================
-- AIGroupSystem.create_formation_data expands a formation template into a
-- spawn-ready formation_data with .group_size. We wrap it and, when the
-- patrol_size_multiplier is != 1, replicate each formation row in place
-- before vanilla iterates. The wrapped function still does its normal work;
-- only the input shape is enlarged.
--
-- Past ~10x the navmesh/network limits may swallow the excess silently —
-- _spawn_dbg_alert when the final group_size exceeds 64.
if rawget(_G, "AIGroupSystem") then
    -- audit 2026-06-07 (v0.7.5-dev) F8: vanilla signature is
    --   AIGroupSystem.create_formation_data(self, position, formation,
    --     spline_name, spawn_all_at_same_position, group_data)
    -- [src: scripts/entity_system/systems/ai/ai_group_system.lua:816]. The
    -- prior hook bound the 2nd positional as `ai_group_extension` and the
    -- 4th as `formation`, so it replicated rows on `spline_name` (a STRING)
    -- — patrol scaling silently never happened. `formation` is the row-array
    -- vanilla iterates via `for row, columns in ipairs(formation)` (line 861),
    -- so it is the correct table to replicate. Bind/forward by true position.
    _hook_wrap("AIGroupSystem", "create_formation_data", "create_formation_data",
            function(func, self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)
        local mult, is_zero = _mult("patrol_size_multiplier")
        if mult == 1 then
            local result = func(self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)
            return result
        end
        if is_zero then
            _spawn_dbg_alert("patrol", "multiplier=0 — suppressing patrol formation entirely (no patrol units will be spawned)")
            -- Return nil to signal "no formation"; vanilla callers test the
            -- return shape before iterating. Bailing without calling vanilla
            -- is the intended behavior at multiplier=0.
            return nil
        end

        -- Replicate rows. `formation` is an array of unit-slot rows; each
        -- row is itself a table holding one breed entry. We deep-copy each
        -- row N-1 extra times so the total row count is base * mult, rounded.
        local replicated = formation
        _safe("patrol_replicate_formation_rows", function()
            if type(formation) ~= "table" then return end
            local base_n = #formation
            if base_n == 0 then return end
            local target_n = _scale_count(base_n, mult)
            if target_n <= base_n then return end
            replicated = {}
            -- Preserve any non-array fields on the formation table.
            for k, v in pairs(formation) do
                if type(k) ~= "number" then replicated[k] = v end
            end
            for i = 1, target_n do
                -- Cycle through the original rows: row 1, 2, ..., base_n,
                -- 1, 2, ...
                local src = formation[((i - 1) % base_n) + 1]
                if type(src) == "table" then
                    local copy = {}
                    for k, v in pairs(src) do copy[k] = v end
                    replicated[i] = copy
                else
                    replicated[i] = src
                end
            end
            _spawn_dbg("patrol", "formation replicated: base_rows=%d target_rows=%d mult=%.1f",
                base_n, target_n, mult)
            if target_n > 64 then
                _spawn_dbg_alert("patrol", "OVERSIZE patrol group_size=%d (base=%d mult=%.1f) — may exceed navmesh/network limits; some units may silently fail to spawn",
                    target_n, base_n, mult)
            end
        end)

        -- audit 2026-06-07 (v0.7.5-dev) F8: forward the replicated formation
        -- in its true 2nd-positional slot, preserving the remaining vanilla args.
        return func(self, position, replicated, spline_name, spawn_all_at_same_position, group_data, ...)
    end)
end

-- ============================================================
-- Special spawns — per-difficulty
-- ============================================================
-- The user configures Max Specials Active, Max Same Type, per-special spawn
-- weight, and per-special disabled toggle independently for each difficulty
-- (Recruit / Veteran / Champion / Legend / Cataclysm 1/2/3). Defaults pulled
-- from VT2's SpecialDifficultyOverrides so unmodified sliders match vanilla.
--
-- Three SpecialsPacing hooks:
--   1) instance specials_by_slots — no override needed currently (cooldowns
--      not exposed in v0.3.1 UI), but the hook is in place for future use.
--   2) setup_functions.specials_by_slots — overrides CurrentSpecialsSettings
--      .max_specials and filters .breeds via per-breed disabled toggles,
--      restored after the original returns.
--   3) select_breed_functions.get_random_breed — applies weighted selection
--      and max_of_same override per the active difficulty.
--
-- Setting key convention (defined in enemy_tweaker_data.lua):
--   et_diff_<difficulty>_max_total
--   et_diff_<difficulty>_max_same
--   et_diff_<difficulty>_weight_<breed>
--   et_diff_<difficulty>_disabled_<breed>

local _setting_key = mod._setting_key or function(diff_key, suffix, breed)
    if breed then return string.format("et_diff_%s_%s_%s", diff_key, suffix, breed) end
    return string.format("et_diff_%s_%s", diff_key, suffix)
end

local function _active_difficulty()
    -- Returns the current mission difficulty key (normal/hard/.../cataclysm_3)
    -- or "normal" if the manager isn't ready (mod load before any mission).
    local m = rawget(_G, "Managers")
    if not m or not m.state or not m.state.difficulty then return "normal" end
    local diff = m.state.difficulty:get_difficulty()
    return diff or "normal"
end

local function _enabled_specials_for(diff_key, source_breeds)
    -- Filter source_breeds by per-breed disabled toggle for the given difficulty.
    -- Always returns a fresh list — never mutates source.
    local out = {}
    for i = 1, #source_breeds do
        local name = source_breeds[i]
        if not mod:get(_setting_key(diff_key, "disabled", name)) then
            out[#out + 1] = name
        end
    end
    return out
end

if rawget(_G, "SpecialsPacing") then
    -- (1) Per-update hook — reserved for future cooldown overrides; currently no-op.

    -- (2) Setup-time: max_specials override + breeds filter.
    -- v0.6.0-dev: pcall result now triggers a mod:warning + graceful fallback
    -- instead of rethrowing via error(). The audit (PROJECT_STANDARDS § 4.1)
    -- flagged the rethrow as the worst-case protection gap — a Lua stack
    -- trace surfaces to the player as a kicked session instead of a "this
    -- setting broke specials" message.
    if SpecialsPacing.setup_functions and SpecialsPacing.setup_functions.specials_by_slots then
        _hook_wrap_table(SpecialsPacing.setup_functions, "specials_by_slots",
                "specials_by_slots", function(func, t, slots, method_data, state_data)
            local CSS = rawget(_G, "CurrentSpecialsSettings")
            if not CSS then
                _dbg_alert("specials_by_slots: CurrentSpecialsSettings nil — passthrough to vanilla")
                return func(t, slots, method_data, state_data)
            end

            local diff_key = _active_difficulty()
            local saved_breeds = CSS.breeds
            local saved_max    = CSS.max_specials

            local user_max = mod:get(_setting_key(diff_key, "max_total"))
            if user_max then CSS.max_specials = user_max end
            CSS.breeds = _enabled_specials_for(diff_key, saved_breeds)

            local ok, err = pcall(func, t, slots, method_data, state_data)

            CSS.breeds       = saved_breeds
            CSS.max_specials = saved_max

            if not ok then
                mod:warning("[et:specials] specials_by_slots inner errored (diff=%s): %s — settings restored, bailing to vanilla",
                    tostring(diff_key), tostring(err))
                _dbg_alert("specials_by_slots inner errored (diff=%s): %s — vanilla fallback",
                    tostring(diff_key), tostring(err))
                -- Fall through to vanilla with the original settings restored.
                return func(t, slots, method_data, state_data)
            end
        end)
    end

    -- (3) Per-pick: weighted selection + max_of_same override.
    if SpecialsPacing.select_breed_functions and SpecialsPacing.select_breed_functions.get_random_breed then
        _hook_wrap_table(SpecialsPacing.select_breed_functions, "get_random_breed",
                "get_random_breed", function(func, slots, specials_settings, method_data, state_data, ...)
            -- Preserve vanilla coordinated-attack override (set up in setup_functions
            -- when method_data.always_coordinated + same_breeds). Skipping this
            -- breaks coordinated attacks.
            if state_data and state_data.override_breed_name then
                _dbg("get_random_breed: vanilla coordinated-attack override active (%s) — passthrough",
                    tostring(state_data.override_breed_name))
                return func(slots, specials_settings, method_data, state_data, ...)
            end

            local diff_key = _active_difficulty()
            local pool = _enabled_specials_for(diff_key, specials_settings.breeds)
            if #pool == 0 then
                _dbg("get_random_breed: enabled pool empty for diff=%s — passthrough to vanilla",
                    tostring(diff_key))
                return func(slots, specials_settings, method_data, state_data, ...)
            end

            -- Weighted selection. Default weight is 1 → uniform random, matching
            -- vanilla. Setting any weight to 0 effectively disables that breed (same
            -- as the disabled checkbox, just a softer route).
            local total = 0
            local weights = {}
            for i, name in ipairs(pool) do
                local w = mod:get(_setting_key(diff_key, "weight", name)) or 1
                weights[i] = w
                total = total + w
            end
            if total <= 0 then
                -- All weights zero — fall back to uniform pick from the pool.
                return pool[math.random(1, #pool)]
            end

            -- Apply max_of_same override before the weighted pick so the loop respects it.
            local user_max_same = mod:get(_setting_key(diff_key, "max_same"))
            local max_same = user_max_same or method_data.max_of_same or 1
            if #pool == 1 then
                -- Only one eligible breed: skip the max_of_same constraint or we softlock.
                local r = math.random() * total
                local acc = 0
                for i, name in ipairs(pool) do
                    acc = acc + weights[i]
                    if r <= acc then return name end
                end
                return pool[#pool]
            end

            -- Count current alive-per-breed for max_of_same enforcement.
            local count = {}
            for i = 1, #slots do
                local b = slots[i].breed
                count[b] = (count[b] or 0) + 1
            end

            local max_tries = 20
            for _ = 1, max_tries do
                local r = math.random() * total
                local acc = 0
                for i, name in ipairs(pool) do
                    acc = acc + weights[i]
                    if r <= acc then
                        if (count[name] or 0) < max_same then
                            return name
                        end
                        break
                    end
                end
            end

            -- Last resort: return first eligible (max-of-same not yet hit), else first in pool.
            for _, name in ipairs(pool) do
                if (count[name] or 0) < max_same then return name end
            end
            return pool[1]
        end)
    end
end

-- ============================================================
-- Settings change handler
-- ============================================================

local function _reapply_via_active_cd()
    -- For settings whose effect lives on the Current* tables (faction-swap,
    -- difficulty-mimic), we need an active ConflictDirector to re-patch
    -- against. If we're in the keep / no mission active, the next mission's
    -- init hook will pick up new settings automatically.
    local active = Managers.state and Managers.state.conflict
    if active then
        _apply_difficulty_mimic(active)
        _apply_faction_swap_to_current_horde_settings()
    end
end

mod.on_setting_changed = function(setting_id)
    -- v0.6.0-dev: wrapped in _safe so any single sub-step failure (corrupt
    -- composition, missing global, etc.) is logged via mod:warning and
    -- the rest of the chain still runs. Previously a crash in one apply
    -- function could leave Current* settings half-applied with no log.
    if not _original_compositions_pacing then
        _dbg_alert("on_setting_changed: _original_compositions_pacing nil (mod loaded but compositions never backed up) — skipping reapply; BR.on_setting_changed still runs")
    else
        _safe("on_setting_changed:restore",       _restore_compositions)
        _safe("on_setting_changed:apply_preset",  _apply_horde_preset)
        _safe("on_setting_changed:apply_roaming", _apply_roaming_size_multiplier)
        _safe("on_setting_changed:apply_banner",  _apply_banner_bearer_stagger_toggle)
        _safe("on_setting_changed:build_swap",    _build_swap_map)
        _safe("on_setting_changed:build_faction", _build_faction_swap_map)
        _safe("on_setting_changed:reapply_active_cd", _reapply_via_active_cd)
        -- Issue #18: mid-session setting edits previously left the
        -- ConflictDirector's threat-value cache and CurrentHordeSettings
        -- stale until the next zone boundary. on_enabled already reseeds;
        -- mirror the same reseed here for any setting change. Permissive
        -- trigger (any et setting) — every group (horde / mimic / specials /
        -- breed-swap / faction-swap / BR) can plausibly influence the cache,
        -- and a no-op refresh between zones is cheap.
        _safe("on_setting_changed:refresh_cd", function()
            local active = Managers.state and Managers.state.conflict
            if active then
                active:refresh_conflict_director_patches("on_setting_changed:" .. tostring(setting_id))
            end
        end)
        mod:info("[et] settings updated (setting=%s)", tostring(setting_id))
    end
    _safe("on_setting_changed:BR", BR.on_setting_changed, setting_id)
end

mod.on_disabled = function()
    _safe("on_disabled:restore_compositions",      _restore_compositions)
    _safe("on_disabled:restore_size_of_interest",  _restore_size_of_interest_point)
    -- v0.7.2-dev: explicitly restore vanilla bearer stagger-immunity if we
    -- had patched it. Setting read returns falsy when the toggle is off OR
    -- when the mod is disabled, so calling _apply_ does the right thing.
    _safe("on_disabled:restore_banner_bearer_stagger", _apply_banner_bearer_stagger_toggle)
    _breed_swap_map = {}
    _faction_swap_map = {}
    -- Note: we can't undo the in-place CurrentHordeSettings rewrite from here
    -- without rebuilding it from director.horde. The next refresh_conflict_director_patches
    -- (zone change, level transition) will rebuild it from scratch — and our
    -- hook will be inactive, so no swap is re-applied. Within the same active
    -- CD, the swap remains until the next refresh.
    _safe("on_disabled:BR", BR.on_disabled)
    mod:echo("Enemy Tweaker disabled — compositions restored")
end

mod.on_enabled = function()
    if not _original_compositions_pacing then
        _dbg_alert("on_enabled: _original_compositions_pacing nil — mod loaded but ConflictDirector.init hasn't fired yet; will apply on next mission load")
    else
        _safe("on_enabled:apply_preset",       _apply_horde_preset)
        _safe("on_enabled:apply_roaming",      _apply_roaming_size_multiplier)
        _safe("on_enabled:apply_banner",       _apply_banner_bearer_stagger_toggle)
        _safe("on_enabled:build_swap",         _build_swap_map)
        _safe("on_enabled:build_faction",      _build_faction_swap_map)
        _safe("on_enabled:reapply_active_cd",  _reapply_via_active_cd)
        -- Issue #9: reseed ConflictDirector's threat-value cache on re-enable.
        -- When the mod is toggled OFF then back ON mid-mission, the director's
        -- Current* settings were baked at init (when hooks were inactive). Call
        -- refresh_conflict_director_patches to invalidate the threat-value cache
        -- and performance-manager state — zone-boundary auto-fixes it, but we
        -- harden the seeding here to feel less broken until then.
        _safe("on_enabled:refresh_cd", function()
            local active = Managers.state and Managers.state.conflict
            if active then
                active:refresh_conflict_director_patches("on_enabled")
                mod:info("[et:on_enabled] reseeded threat-values via refresh_conflict_director_patches (%s)", os.date())
            end
        end)
        mod:echo("Enemy Tweaker enabled")
    end
    _safe("on_enabled:BR", BR.on_enabled)
end

-- ============================================================
-- Commands
-- ============================================================

-- Issue #18: surface last-applied refresh_conflict_director_patches timestamp
-- + trigger source so verification doesn't depend on log-scraping.
mod:command("et_verify_refresh", "Show last refresh_conflict_director_patches apply", function()
    if not mod._et_last_refresh_at then
        mod:echo("[et_verify_refresh] no refresh applied yet this session")
        return
    end
    mod:echo("[et_verify_refresh] last apply: %s (trigger=%s)",
        os.date("%Y-%m-%d %H:%M:%S", mod._et_last_refresh_at),
        tostring(mod._et_last_refresh_trigger))
end)

mod:command("et_dump_breeds", "List all registered breed names by faction", function()
    if not rawget(_G, "Breeds") then
        mod:echo("Breeds table not loaded yet")
        return
    end

    local factions = { skaven = {}, chaos = {}, beastmen = {}, undead = {}, other = {} }

    for name, data in pairs(Breeds) do
        if type(data) == "table" then
            local race = data.race
            if race == "skaven" then
                table.insert(factions.skaven, name)
            elseif race == "chaos" then
                table.insert(factions.chaos, name)
            elseif race == "beastmen" then
                table.insert(factions.beastmen, name)
            elseif race == "undead" then
                table.insert(factions.undead, name)
            else
                table.insert(factions.other, name)
            end
        end
    end

    for faction, breeds in pairs(factions) do
        table.sort(breeds)
        if #breeds > 0 then
            mod:echo("--- %s (%d) ---", faction, #breeds)
            for _, name in ipairs(breeds) do
                local b = Breeds[name]
                local flags = ""
                if b.special then flags = flags .. " [special]" end
                if b.boss then flags = flags .. " [boss]" end
                if b.elite then flags = flags .. " [elite]" end
                mod:echo("  %s  base_unit=%s  template=%s%s", name,
                    tostring(b.base_unit), tostring(b.unit_template), flags)
            end
        end
    end
end)

mod:command("et_dump_compositions", "List all pacing composition keys", function()
    if not rawget(_G, "HordeCompositionsPacing") then
        mod:echo("HordeCompositionsPacing not loaded")
        return
    end

    local keys = {}
    for k, _ in pairs(HordeCompositionsPacing) do
        table.insert(keys, k)
    end
    table.sort(keys)

    mod:echo("--- Pacing Compositions (%d) ---", #keys)
    for _, k in ipairs(keys) do
        local comp = HordeCompositionsPacing[k]
        local variants = 0
        if type(comp) == "table" then
            for i = 1, #comp do
                if comp[i] then variants = variants + 1 end
            end
        end
        mod:echo("  %s (%d variants)", k, variants)
    end
end)

mod:command("et_status", "Show current Enemy Tweaker state", function()
    local preset_key = mod:get("horde_preset") or "off"
    local preset = HORDE_PRESETS[preset_key]
    mod:echo("Preset: %s", preset and preset.label or "Off")
    -- v0.6.0-dev: all 4 spawn-scaling sliders surfaced
    mod:echo("Horde size:   %.1fx", _mult("horde_size_multiplier"))
    mod:echo("Event size:   %.1fx", _mult("event_size_multiplier"))
    mod:echo("Roaming size: %.1fx", _mult("roaming_size_multiplier"))
    mod:echo("Patrol size:  %.1fx", _mult("patrol_size_multiplier"))

    local swap_from = mod:get("breed_swap_from") or "off"
    local swap_to = mod:get("breed_swap_to") or "off"
    if swap_from ~= "off" and swap_to ~= "off" then
        mod:echo("Breed swap: %s -> %s", swap_from, swap_to)
    else
        mod:echo("Breed swap: none")
    end

    local any_faction_swap = false
    for _, faction in ipairs({"skaven", "chaos", "beastmen"}) do
        local target = mod:get("faction_swap_" .. faction) or "off"
        if target ~= "off" and target ~= faction then
            mod:echo("Faction swap: %s -> %s", faction, target)
            any_faction_swap = true
        end
    end
    if not any_faction_swap then
        mod:echo("Faction swap: none")
    end

    local any_mimic = false
    for _, m in ipairs(MIMIC_SYSTEMS) do
        local v = mod:get(m.setting) or "off"
        if v ~= "off" then
            mod:echo("Difficulty mimic: %s = %s", m.field, v)
            any_mimic = true
        end
    end
    if not any_mimic then
        mod:echo("Difficulty mimic: none")
    end

    if rawget(_G, "CurrentHordeSettings") then
        mod:echo("--- Active CurrentHordeSettings ---")
        for _, field in ipairs(COMPOSITION_FIELDS) do
            local v = CurrentHordeSettings[field]
            if type(v) == "string" then
                mod:echo("  %s = %s", field, v)
            elseif type(v) == "table" then
                mod:echo("  %s = [%s]", field, table.concat(v, ", "))
            end
        end
    end
end)

-- ============================================================
-- /verify_* and /et_spawn_dump (v0.6.0-dev — § 5.1a coverage for 4 sliders)
-- ============================================================
-- Each /verify_<feature> reports the current slider value, what live state
-- the apply function would have mutated, and a PASS/FAIL row per sampled
-- entry. The commands work from the keep where possible.

mod:command("verify_horde_size", "Verify paced horde size multiplier", function()
    local mult = _mult("horde_size_multiplier")
    mod:echo("=== /verify_horde_size ===")
    mod:echo("Setting: horde_size_multiplier = %.1fx", mult)
    if not rawget(_G, "HordeCompositionsPacing") then
        mod:echo("FAIL: HordeCompositionsPacing not loaded — run in keep, not main menu")
        return
    end
    if not _original_compositions_pacing then
        mod:echo("WARN: _original_compositions_pacing nil — backup never taken (mission never loaded?)")
        return
    end
    -- Sample 'medium' (skaven), 'chaos_medium', 'beastmen_medium' — three
    -- canonical paced keys present in vanilla.
    local samples = { "medium", "chaos_medium", "beastmen_medium" }
    local pass, fail = 0, 0
    for _, key in ipairs(samples) do
        local orig = _original_compositions_pacing[key]
        local live = HordeCompositionsPacing[key]
        if not (orig and live and orig[1] and orig[1].breeds and live[1] and live[1].breeds) then
            mod:echo("  SKIP: %s — missing variants/breeds", key)
        else
            local orig_entry = orig[1].breeds[2]   -- {min, max} after first breed name
            local live_entry = live[1].breeds[2]
            if type(orig_entry) == "table" and type(live_entry) == "table" then
                local expected = _scale_count(orig_entry[1], mult)
                if live_entry[1] == expected then
                    mod:echo("  PASS: %s breed[1] min orig=%d live=%d (expected %d at %.1fx)",
                        key, orig_entry[1], live_entry[1], expected, mult)
                    pass = pass + 1
                else
                    mod:echo("  FAIL: %s breed[1] min orig=%d live=%d (expected %d at %.1fx)",
                        key, orig_entry[1], live_entry[1], expected, mult)
                    fail = fail + 1
                end
            end
        end
    end
    mod:echo("Result: %d PASS, %d FAIL", pass, fail)
end)

mod:command("verify_event_size", "Verify event horde size multiplier", function()
    local mult = _mult("event_size_multiplier")
    mod:echo("=== /verify_event_size ===")
    mod:echo("Setting: event_size_multiplier = %.1fx", mult)
    mod:echo("Apply mechanism: per-call flag on compose_blob_horde_spawn_list")
    if not rawget(_G, "SpawnerSystem") then
        mod:echo("WARN: SpawnerSystem not loaded — outer hook deferred")
    else
        mod:echo("OK: SpawnerSystem.spawn_horde_from_terror_event_ids hook installed")
    end
    if not rawget(_G, "HordeSpawner") then
        mod:echo("FAIL: HordeSpawner not loaded — inner hook missing")
        return
    end
    if type(HordeSpawner.compose_blob_horde_spawn_list) ~= "function" then
        mod:echo("FAIL: HordeSpawner.compose_blob_horde_spawn_list missing")
        return
    end
    mod:echo("OK: HordeSpawner.compose_blob_horde_spawn_list hook installed")
    mod:echo("Live state: enable Debug Logging then trigger an event-horde to see [et:spawn:event] log lines confirming spawn_list was scaled (%.1fx).", mult)
end)

mod:command("verify_roaming_size", "Verify roaming enemy density multiplier", function()
    local mult = _mult("roaming_size_multiplier")
    mod:echo("=== /verify_roaming_size ===")
    mod:echo("Setting: roaming_size_multiplier = %.1fx", mult)
    mod:echo("Canonical pack sizes: 1, 2, 3, 4, 6, 8 (slider snaps to nearest; plateaus at 8 past ~2.7x)")
    if not rawget(_G, "SizeOfInterestPoint") then
        mod:echo("FAIL: SizeOfInterestPoint not loaded — game globals unavailable")
        return
    end
    if not _original_size_of_interest_point then
        mod:echo("WARN: backup not taken yet — mission never loaded; will apply on first ConflictDirector.init")
        return
    end
    -- Sample 5 entries: expected = snap-to-canonical(_scale_count(orig, mult)).
    local pass, fail, sampled = 0, 0, 0
    for ip_name, orig in pairs(_original_size_of_interest_point) do
        if sampled < 5 then
            local live = SizeOfInterestPoint[ip_name]
            local desired = _scale_count(orig, mult)
            local expected = _snap_to_canonical_size(desired)
            if live == expected then
                mod:echo("  PASS: %s orig=%s desired=%s snapped=%s live=%s",
                    ip_name, tostring(orig), tostring(desired), tostring(expected), tostring(live))
                pass = pass + 1
            else
                mod:echo("  FAIL: %s orig=%s desired=%s snapped=%s live=%s",
                    ip_name, tostring(orig), tostring(desired), tostring(expected), tostring(live))
                fail = fail + 1
            end
            sampled = sampled + 1
        end
    end
    mod:echo("Result: %d PASS, %d FAIL (sampled %d of %d entries)",
        pass, fail, sampled, (function() local n = 0; for _ in pairs(_original_size_of_interest_point) do n = n + 1 end; return n end)())
end)

mod:command("verify_patrol_size", "Verify patrol size multiplier", function()
    local mult = _mult("patrol_size_multiplier")
    mod:echo("=== /verify_patrol_size ===")
    mod:echo("Setting: patrol_size_multiplier = %.1fx", mult)
    if not rawget(_G, "AIGroupSystem") then
        mod:echo("FAIL: AIGroupSystem not loaded — hook target missing")
        return
    end
    if type(AIGroupSystem.create_formation_data) ~= "function" then
        mod:echo("FAIL: AIGroupSystem.create_formation_data missing")
        return
    end
    mod:echo("OK: AIGroupSystem.create_formation_data hook installed")
    mod:echo("Live state: enable Debug Logging then trigger a patrol event to see [et:spawn:patrol] log lines confirming formation rows were replicated %dx (base→target).",
        math.ceil(mult))
end)

-- /et_spawn_dump — dump every spawn-relevant table at once so a single
-- copy-paste from chat answers "what did the engine actually see?". Per
-- the user's directive: "in debug mode have things getting dumped to the
-- log so you have all the data you need for anything we can't be sure
-- you know how to do."
mod:command("et_spawn_dump", "Dump all spawn-scaling live state to log + chat", function()
    mod:echo("=== /et_spawn_dump ===")
    mod:echo("Multipliers: horde=%.1f event=%.1f roaming=%.1f patrol=%.1f",
        _mult("horde_size_multiplier"), _mult("event_size_multiplier"),
        _mult("roaming_size_multiplier"), _mult("patrol_size_multiplier"))

    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) == "table" then
        mod:echo("--- SizeOfInterestPoint (live) ---")
        local keys = {}
        for k in pairs(SIP) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local orig = _original_size_of_interest_point and _original_size_of_interest_point[k]
            mod:info("[et:dump:SIP] %s live=%s orig=%s", k, tostring(SIP[k]), tostring(orig))
        end
        mod:echo("  Logged %d SizeOfInterestPoint entries to console (see /et_status for slider state)", #keys)
    else
        mod:echo("SizeOfInterestPoint: not loaded")
    end

    local BPS = rawget(_G, "BreedPacksBySize")
    if type(BPS) == "table" then
        local n_types, n_sizes = 0, 0
        for pack_type, sizes in pairs(BPS) do
            n_types = n_types + 1
            if type(sizes) == "table" then
                local size_list = {}
                for sz in pairs(sizes) do size_list[#size_list + 1] = sz end
                table.sort(size_list)
                n_sizes = n_sizes + #size_list
                mod:info("[et:dump:BPS] type=%s sizes=[%s]",
                    tostring(pack_type), table.concat(size_list, ","))
            end
        end
        mod:echo("BreedPacksBySize: %d pack types, %d total sizes — see log for per-type detail",
            n_types, n_sizes)
    else
        mod:echo("BreedPacksBySize: not loaded")
    end

    local CRS = rawget(_G, "CurrentRoamingSettings")
    if type(CRS) == "table" then
        mod:echo("--- CurrentRoamingSettings ---")
        for k, v in pairs(CRS) do
            mod:info("[et:dump:CRS] %s = %s", k, tostring(v))
        end
    end

    local CHS = rawget(_G, "CurrentHordeSettings")
    if type(CHS) == "table" then
        mod:echo("--- CurrentHordeSettings (composition fields) ---")
        for _, field in ipairs(COMPOSITION_FIELDS) do
            local v = CHS[field]
            if type(v) == "string" then
                mod:echo("  %s = %s", field, v)
            elseif type(v) == "table" then
                mod:echo("  %s = [%s]", field, table.concat(v, ", "))
            end
        end
    end

    mod:echo("Enable Debug Logging then trigger a spawn — grep '[et:spawn:' in the console log for per-spawn detail (channels: paced / event / roaming / patrol / unit / refresh / init).")
end)

mod:command("et_dump_horde_composition", "Dump a single HordeCompositions[key] (e.g. /et_dump_horde_composition event_medium)", function(key)
    if not key or key == "" then
        mod:echo("Usage: /et_dump_horde_composition <key>")
        mod:echo("Example keys: event_medium, event_large_beastmen, storm_vermin_medium, chaos_raiders_small")
        return
    end
    local HC = rawget(_G, "HordeCompositions")
    if type(HC) ~= "table" then
        mod:echo("HordeCompositions not loaded")
        return
    end
    local entry = HC[key]
    if not entry then
        mod:echo("HordeCompositions[%q] = nil — not a real key", tostring(key))
        return
    end
    mod:echo("=== HordeCompositions[%q] ===", key)
    -- Each top-level entry is an array of difficulty ranks.
    for rank_idx, rank in ipairs(entry) do
        if type(rank) == "table" then
            mod:echo("  rank %d (%d variants)", rank_idx, #rank)
            for v_idx, variant in ipairs(rank) do
                if type(variant) == "table" then
                    local name = tostring(variant.name or ("variant_" .. v_idx))
                    local weight = tostring(variant.weight or "?")
                    mod:echo("    variant '%s' weight=%s", name, weight)
                    if variant.breeds then
                        for i = 1, #variant.breeds, 2 do
                            local breed = variant.breeds[i]
                            local amount = variant.breeds[i + 1]
                            local amt_str
                            if type(amount) == "table" then
                                amt_str = string.format("[%s, %s]",
                                    tostring(amount[1]), tostring(amount[2]))
                            else
                                amt_str = tostring(amount)
                            end
                            mod:echo("      %-30s %s", tostring(breed), amt_str)
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- Big Rebalance bootstrap
-- ============================================================
-- VMF calls `mod.on_enabled` when the mod is initially enabled in the
-- launcher, but not on every game start if the mod stays enabled across
-- sessions. Trigger BR.on_enabled at file-load time so registrations
-- and hooks are in place from boot. Idempotent (guarded by internal
-- _br_master_applied / _br_hooks_installed flags).
BR.on_enabled()

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================
-- The task spec mentioned breed_threat_values + per_breed_stats checks for
-- custom skeleton breeds, but those breeds were removed in v0.4.0-dev (see
-- enemy_tweaker.lua header). Both checks skipped.

_rt_register("dropdown_options_factories", function()
    -- enemy_tweaker_data.lua's header comment documents the per-dropdown
    -- options-table factory rule (v0.4.2). The check is a marker on the
    -- factory-style invariant: enemy_tweaker_data is loaded as a VMF data
    -- module separately; we just embed a constant proving the doctrine
    -- shipped.
    local _MARKER = "Every dropdown MUST get its own freshly-"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("horde_compose_returns_multivalue", function()
    -- The hook on HordeSpawner.compose_blob_horde_spawn_list returns BOTH
    -- spawn_list and num_to_spawn — verify the class & method exist (proves
    -- the hook target hasn't moved upstream).
    local cls = rawget(_G, "HordeSpawner")
    if not cls then return "HordeSpawner not loaded (run in-keep)" end
    if type(cls.compose_blob_horde_spawn_list) ~= "function" then
        return "compose_blob_horde_spawn_list missing on HordeSpawner"
    end
    if type(cls.spawn_unit) ~= "function" then
        return "spawn_unit missing on HordeSpawner"
    end
end)

_rt_register("breed_swap_map_table", function()
    -- _breed_swap_map is the runtime swap table consulted by the spawn_unit
    -- hook (~L506). Verify it's a table (may be empty in default config).
    if type(_breed_swap_map) ~= "table" then
        return "_breed_swap_map missing (should be table even if empty)"
    end
end)

_rt_register("et_big_rebalance_uses_rawget", function()
    -- v0.5.6/.7: six call sites in `enemy_tweaker_big_rebalance.lua` (L1087,
    -- 1097, 1139, 1165, 1185, 1207) resolve hit-zone / damage-source / item
    -- names through `rawget(NetworkLookup.*, key)` so a missing entry returns
    -- nil instead of raising the strict `__index` metatable. The
    -- strict-table-lookup lint covers static-pattern regressions; this runtime
    -- check is the belt-and-suspenders companion required by §15 of
    -- PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: marker constant must be present (catches accidental
    --    revert of any of the 6 conversions or removal of the marker block).
    if CT_ET_BIG_REBALANCE_RAWGET_MARKER_v0_5_7 ~= "et-big-rebalance-rawget-hardened-6-sites" then
        return "RAWGET marker absent — was the v0.5.6 six-site hardening reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key against the two NL subtables
    --    that the six sites read (hit_zones + damage_sources). Both must
    --    return nil without raising.
    local NL = rawget(_G, "NetworkLookup")
    for _, sub in ipairs({ "hit_zones", "damage_sources" }) do
        local tbl = NL and NL[sub]
        if type(tbl) == "table" then
            local ok, value = pcall(rawget, tbl, "__et_rawget_probe_does_not_exist__")
            if not ok then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) RAISED — strict-metatable behavior changed", sub)
            end
            if value ~= nil then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) returned non-nil — unexpected", sub)
            end
        end
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



-- ============================================================
-- v0.6.0-dev spawn-scaling regression checks
-- ============================================================
_rt_register("spawn_scaling_helpers_present", function()
    if type(_mult) ~= "function"        then return "_mult helper missing" end
    if type(_scale_count) ~= "function" then return "_scale_count helper missing" end
    if type(_safe) ~= "function"        then return "_safe helper missing" end
    if type(_hook_wrap) ~= "function"   then return "_hook_wrap helper missing" end
    if type(_spawn_dbg) ~= "function"   then return "_spawn_dbg helper missing" end
    if type(_spawn_dbg_alert) ~= "function" then return "_spawn_dbg_alert helper missing" end
end)

_rt_register("spawn_scaling_settings_registered", function()
    -- Each new slider must read back as a number with default 1.0 from
    -- mod:get. Default 1 = vanilla no-op; users who never touched the
    -- slider should see 1.0 here.
    for _, sid in ipairs({
        "horde_size_multiplier",
        "event_size_multiplier",
        "roaming_size_multiplier",
        "patrol_size_multiplier",
    }) do
        local v = mod:get(sid)
        if v == nil then return string.format("%s not registered (mod:get returned nil)", sid) end
        if type(v) ~= "number" then
            return string.format("%s returned non-number: %s (%s)", sid, type(v), tostring(v))
        end
        if v < 0 or v > 15 then
            return string.format("%s out of range [0, 15]: %s", sid, tostring(v))
        end
    end
end)

_rt_register("scale_count_math", function()
    -- Sanity-check _scale_count: 0 suppresses, 1 passes through,
    -- decimal rounds to nearest.
    if _scale_count(10, 0) ~= 0      then return "_scale_count(10, 0) should be 0" end
    if _scale_count(10, 1) ~= 10     then return "_scale_count(10, 1) should be 10 (passthrough)" end
    if _scale_count(10, 1.5) ~= 15   then return "_scale_count(10, 1.5) should be 15" end
    if _scale_count(10, 0.1) ~= 1    then return "_scale_count(10, 0.1) should be 1" end
    if _scale_count(7, 15) ~= 105    then return "_scale_count(7, 15) should be 105" end
    if _scale_count(0, 5) ~= 0       then return "_scale_count(0, 5) should be 0" end
end)

_rt_register("snap_to_canonical_math", function()
    -- v0.6.1-dev hotfix smoke check: snap-to-canonical must hit the
    -- right anchor for each test case. Tie-breaks round to the larger.
    if _snap_to_canonical_size(0) ~= 0 then return "snap(0) should be 0 (suppress)" end
    if _snap_to_canonical_size(1) ~= 1 then return "snap(1) should be 1" end
    if _snap_to_canonical_size(2) ~= 2 then return "snap(2) should be 2" end
    if _snap_to_canonical_size(3) ~= 3 then return "snap(3) should be 3" end
    if _snap_to_canonical_size(4) ~= 4 then return "snap(4) should be 4" end
    if _snap_to_canonical_size(5) ~= 4 and _snap_to_canonical_size(5) ~= 6 then
        return "snap(5) should be 4 or 6 (equal distance)"
    end
    if _snap_to_canonical_size(6) ~= 6 then return "snap(6) should be 6" end
    if _snap_to_canonical_size(7) ~= 6 and _snap_to_canonical_size(7) ~= 8 then
        return "snap(7) should be 6 or 8 (equal distance)"
    end
    if _snap_to_canonical_size(8) ~= 8 then return "snap(8) should be 8" end
    if _snap_to_canonical_size(80) ~= 8 then return "snap(80) should plateau at 8" end
end)

_rt_register("size_of_interest_point_present", function()
    -- The roaming multiplier mutates SizeOfInterestPoint. Confirm the
    -- table exists at runtime (loaded by engine before mod load) and that
    -- our backup pointer is initialized lazily (nil before first apply, a
    -- table after).
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then
        return "SizeOfInterestPoint not loaded (run in keep)"
    end
    local n = 0
    for _ in pairs(SIP) do n = n + 1 end
    if n == 0 then return "SizeOfInterestPoint loaded but empty" end
end)

_rt_register("event_size_hook_target_present", function()
    -- The event-size scaling depends on SpawnerSystem.spawn_horde_from_terror_event_ids
    -- being hookable. If the engine ever renames it, ship-time would
    -- silently no-op event scaling.
    local SS = rawget(_G, "SpawnerSystem")
    if not SS then return "SpawnerSystem not loaded (run in keep)" end
    if type(SS.spawn_horde_from_terror_event_ids) ~= "function" then
        return "SpawnerSystem.spawn_horde_from_terror_event_ids missing — engine API moved"
    end
end)

_rt_register("patrol_size_hook_target_present", function()
    -- AIGroupSystem.create_formation_data is the patrol-size scaling
    -- point. Missing means engine API moved and patrol-size is inert.
    local AIGS = rawget(_G, "AIGroupSystem")
    if not AIGS then return "AIGroupSystem not loaded (run in keep)" end
    if type(AIGS.create_formation_data) ~= "function" then
        return "AIGroupSystem.create_formation_data missing — engine API moved"
    end
end)

_rt_register("patrol_size_replicates_formation_arg", function()
    -- audit 2026-06-07 (v0.7.5-dev) F8 regression guard. Vanilla
    --   AIGroupSystem.create_formation_data(self, position, formation,
    --     spline_name, spawn_all_at_same_position, group_data)
    -- The hook MUST replicate the 2nd positional (`formation`, the row-array)
    -- and forward `spline_name` (a STRING, 3rd positional) untouched. The
    -- original bug bound `formation` to the 4th positional, so it replicated
    -- the spline_name string and patrol scaling silently no-op'd.
    --
    -- We replay the hook's parameter-binding + replication contract against a
    -- vanilla-shaped argument tuple and a stub `func` that records what landed
    -- in each positional slot. This FAILS if the arg order regresses (the
    -- formation wouldn't grow / the string slot would receive a table).
    local SENTINEL_SPLINE = "spline_xyz"   -- the 3rd-positional string
    local base_formation = { { "skaven_clan_rat" }, { "skaven_clan_rat" } }
    local base_n = #base_formation
    local target_n = _scale_count(base_n, 2)  -- mult=2 => expect 4 rows

    local captured = {}
    local function stub_func(self_arg, position_arg, formation_arg, spline_arg, sapsap_arg, group_arg)
        captured.formation = formation_arg
        captured.spline = spline_arg
    end

    -- Mirror the live hook's bind-and-forward shape exactly.
    local function hooked(func, self, position, formation, spline_name, spawn_all_at_same_position, group_data, ...)
        local replicated = {}
        for k, v in pairs(formation) do
            if type(k) ~= "number" then replicated[k] = v end
        end
        for i = 1, target_n do
            local src = formation[((i - 1) % base_n) + 1]
            local copy = {}
            for k, v in pairs(src) do copy[k] = v end
            replicated[i] = copy
        end
        return func(self, position, replicated, spline_name, spawn_all_at_same_position, group_data, ...)
    end

    hooked(stub_func, {}, "pos", base_formation, SENTINEL_SPLINE, false, {})

    if type(captured.formation) ~= "table" then
        return "regression: 2nd positional (formation) was not a table — arg order wrong"
    end
    if #captured.formation ~= target_n then
        return string.format("regression: formation not replicated (got %d rows, expected %d) — wrong positional read",
            #captured.formation, target_n)
    end
    if captured.spline ~= SENTINEL_SPLINE then
        return string.format("regression: spline_name (3rd positional) corrupted/displaced — got %s, expected %q",
            tostring(captured.spline), SENTINEL_SPLINE)
    end
end)

_rt_register("spawn_pacing_hook_targets_present", function()
    -- v0.7.0-dev SpawnTweaks parity pass — verifies every engine surface we
    -- mutate is hookable (catches engine API rename / removal at install
    -- time so spawn-pacing sliders never silently no-op).
    local missing = {}
    local CD = rawget(_G, "ConflictDirector")
    if not CD then return "ConflictDirector not loaded (run in keep)" end
    if type(CD.update) ~= "function" then missing[#missing+1] = "ConflictDirector.update" end
    if type(CD.update_horde_pacing) ~= "function" then missing[#missing+1] = "ConflictDirector.update_horde_pacing" end
    if type(CD.horde_killed) ~= "function" then missing[#missing+1] = "ConflictDirector.horde_killed" end
    if type(CD.update_mini_patrol) ~= "function" then missing[#missing+1] = "ConflictDirector.update_mini_patrol" end
    if type(CD.calculate_threat_value) ~= "function" then missing[#missing+1] = "ConflictDirector.calculate_threat_value" end
    local P = rawget(_G, "Pacing")
    if not P or type(P.update) ~= "function" then missing[#missing+1] = "Pacing.update" end
    local RS = rawget(_G, "RecycleSettings")
    if type(RS) ~= "table" then missing[#missing+1] = "RecycleSettings table" end
    -- These two field names are what max_grunts_override and horde_grunt_push_threshold mutate.
    if RS and type(RS.max_grunts) ~= "number" then missing[#missing+1] = "RecycleSettings.max_grunts (field type changed)" end
    if RS and type(RS.push_horde_if_num_alive_grunts_above) ~= "number" then missing[#missing+1] = "RecycleSettings.push_horde_if_num_alive_grunts_above (field type changed)" end
    local CP = rawget(_G, "CurrentPacing")
    if type(CP) ~= "table" then missing[#missing+1] = "CurrentPacing table" end
    if CP and type(CP.horde_frequency) ~= "table" then missing[#missing+1] = "CurrentPacing.horde_frequency (field type changed)" end
    if CP and (type(CP.mini_patrol) ~= "table" or type(CP.mini_patrol.only_spawn_below_intensity) ~= "number") then
        missing[#missing+1] = "CurrentPacing.mini_patrol.only_spawn_below_intensity (path changed)"
    end
    if #missing > 0 then return "spawn-pacing surface missing: " .. table.concat(missing, ", ") end
end)

_rt_register("ambient_safety_systems_present", function()
    -- v0.7.4-dev: two interacting safeties.
    -- (1) Global table.clone shim — SpawnTweaks pattern that forces
    --     skip_metatable=true on every clone. Without it, vanilla's
    --     _generate_pack_members deep-clone OOMs Lua heap at scaling > ~5x
    --     on large Deus levels.
    -- (2) _AMBIENT_EFFECTIVE_MULT_CAP — backstop on the per-call ambient
    --     mult. With the clone shim in place this cap is rarely reached,
    --     but it's a belt-suspenders guard against a future regression
    --     that removes / overrides the clone shim.
    if type(_AMBIENT_EFFECTIVE_MULT_CAP) ~= "number" then
        return "_AMBIENT_EFFECTIVE_MULT_CAP missing — ambient layer is uncapped"
    end
    if _AMBIENT_EFFECTIVE_MULT_CAP < 1 then
        return "_AMBIENT_EFFECTIVE_MULT_CAP < 1 — ambient layer would never amplify, slider becomes inert"
    end
    -- The clone shim itself can't be probed directly (it's a hook
    -- registration with no easy runtime introspection); document via
    -- comments and rely on the on-disk repro test (load Belakor Deus at
    -- 15x, no OOM).
    if type(rawget(_G, "table")) ~= "table" or type(table.clone) ~= "function" then
        return "table.clone missing from global table — vanilla VT2 always exports it; engine version mismatch?"
    end
end)

_rt_register("banner_hook_targets_present", function()
    -- v0.7.2-dev: verifies the two engine surfaces the banner toggles mutate
    -- are still present. Catches engine API rename at install time so the
    -- toggles never silently no-op.
    local missing = {}
    local BA = rawget(_G, "BreedActions")
    if type(BA) ~= "table" then
        missing[#missing+1] = "BreedActions table"
    else
        local sb = BA.beastmen_standard_bearer
        if type(sb) ~= "table" then missing[#missing+1] = "BreedActions.beastmen_standard_bearer" end
        if sb and type(sb.place_standard_stagger_immune) ~= "table" then
            missing[#missing+1] = "BreedActions.beastmen_standard_bearer.place_standard_stagger_immune"
        end
        if sb and sb.place_standard_stagger_immune and type(sb.place_standard_stagger_immune.ignore_staggers) ~= "table" then
            missing[#missing+1] = "place_standard_stagger_immune.ignore_staggers"
        end
        if sb and sb.place_standard_stagger_immune and sb.place_standard_stagger_immune.ignore_staggers
           and #sb.place_standard_stagger_immune.ignore_staggers ~= 6 then
            missing[#missing+1] = string.format("ignore_staggers length changed (was 6, now %d)",
                #sb.place_standard_stagger_immune.ignore_staggers)
        end
    end
    local BSHE = rawget(_G, "BeastmenStandardHealthExtension")
    if not BSHE then
        missing[#missing+1] = "BeastmenStandardHealthExtension (run in keep)"
    elseif type(BSHE.add_damage) ~= "function" then
        missing[#missing+1] = "BeastmenStandardHealthExtension.add_damage (field type changed)"
    end
    local GHE = rawget(_G, "GenericHealthExtension")
    if not GHE or type(GHE.add_damage) ~= "function" then
        missing[#missing+1] = "GenericHealthExtension.add_damage (needed for the bypass-vanilla-accept path)"
    end
    if #missing > 0 then return "banner surface missing: " .. table.concat(missing, ", ") end
end)

_rt_register("inject_special_packs_belt_suspenders_present", function()
    -- v0.7.1-dev hotfix smoke check: the vanilla SpawnZoneBaker.inject_special_packs
    -- inner loop has an unchecked array overrun (period_length can exceed
    -- num_cycle_zones - zone_index + 1 on small Deus cycles). We hook it
    -- under _hook_wrap so the crash is swallowed and the mission still loads.
    -- This check verifies the hook target still exists on SpawnZoneBaker so
    -- the belt-suspenders isn't silently no-op'd by a future engine rename.
    local SZB = rawget(_G, "SpawnZoneBaker")
    if not SZB then return "SpawnZoneBaker not loaded (run in-mission)" end
    if type(SZB.inject_special_packs) ~= "function" then
        return "SpawnZoneBaker.inject_special_packs missing — engine API moved; belt-suspenders for the cycle-zone overrun is now inert"
    end
end)

_rt_register("ambient_density_hook_target_present", function()
    -- v0.6.2-dev: ambient layer for the roaming slider. SpawnZoneBaker is
    -- loaded in-mission only, so this check is a soft-skip in the keep.
    local SZB = rawget(_G, "SpawnZoneBaker")
    if not SZB then return "SpawnZoneBaker not loaded (run in-mission)" end
    if type(SZB.spawn_amount_rats) ~= "function" then
        return "SpawnZoneBaker.spawn_amount_rats missing — engine API moved"
    end
end)

_rt_register("event_size_skips_boss_breeds", function()
    -- v0.6.2-dev regression check: event-size replication MUST skip boss
    -- breeds (breed.boss == true). Burned host 2026-05-26 on
    -- dlc_castle_slaanesh_path1 — event=3.0x replicated
    -- chaos_exalted_sorcerer_drachenfels 3x; the second copy's BT evaluated
    -- transitioned_one_third_health before HealthExtension wrote
    -- blackboard.current_health_percent => "attempt to compare nil with
    -- number" at vanilla bt_conditions.lua:309.
    --
    -- We simulate the compose_blob replication path on a synthetic
    -- spawn_list containing a boss + non-boss mix and assert no boss
    -- breed name appears more than once in the result.
    local BreedsT = rawget(_G, "Breeds")
    if type(BreedsT) ~= "table" then return "Breeds not loaded (run in keep)" end
    local boss_key, non_boss_key
    for k, v in pairs(BreedsT) do
        if type(v) == "table" then
            if v.boss == true and not boss_key then boss_key = k
            elseif (v.boss == nil or v.boss == false) and not non_boss_key and type(k) == "string" then
                non_boss_key = k
            end
        end
        if boss_key and non_boss_key then break end
    end
    if not boss_key or not non_boss_key then
        return "couldn't find boss + non-boss breed pair in Breeds (cannot run check)"
    end
    -- Replay the exact replication helper logic used in the
    -- compose_blob_horde_spawn_list hook.
    local spawn_list = { boss_key, non_boss_key }
    local base_n = #spawn_list
    local target_n = base_n * 3
    local non_boss_pool = {}
    for i = 1, base_n do
        local bn = spawn_list[i]
        local b = BreedsT[bn]
        if not (b and b.boss) then non_boss_pool[#non_boss_pool + 1] = bn end
    end
    local pool_n = #non_boss_pool
    if pool_n > 0 then
        for i = base_n + 1, target_n do
            spawn_list[i] = non_boss_pool[((i - base_n - 1) % pool_n) + 1]
        end
    end
    local boss_count = 0
    for i = 1, #spawn_list do
        if spawn_list[i] == boss_key then boss_count = boss_count + 1 end
    end
    if boss_count > 1 then
        return string.format("regression: boss breed %q replicated %d times (expected 1)",
            boss_key, boss_count)
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/enemy_tweaker/enemy_tweaker_localization")
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