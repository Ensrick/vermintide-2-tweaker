-- Run creation, node-entry, backend safety, and population orchestration.
-- Existing specialized owners remain installed at their original relative positions.
return function(mod, ctx)
    local BOMB_BOON_NAMES = ctx.bomb_boon_names
    local CHEST_DEFAULT = ctx.chest_default
    local CT_RPC_SCHEMA = ctx.rpc_schema
    local FINALE_GODS = ctx.finale_gods
    local MOD_VERSION = ctx.mod_version
    local REAL_PLAYER_LOCAL_ID = ctx.real_player_local_id
    local SHRINE_DEFAULT = ctx.shrine_default
    local _capture_returns = ctx.capture_returns
    local _collect_setting_ids = ctx.collect_setting_ids
    local _ct_altar_reuse = ctx.altar_reuse
    local _ct_peer_manifest = ctx.peer_manifest
    local _dbg = ctx.dbg
    local _dbg_alert = ctx.dbg_alert
    local _rt_register = ctx.rt_register
    local effective_setting = ctx.effective_setting
    local is_curse_disabled
    local sync_bomb_cooldown = ctx.sync_bomb_cooldown
    local sync_boon_movespeed = ctx.sync_boon_movespeed
    local sync_reckless_swings = ctx.sync_reckless_swings

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
            tostring(ctx.host_sync_received()), #ids)
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

-- ============================================================
-- Run creation: the setup_run seam -> _ct_run_creation_owner.lua (#1159)
-- ============================================================
-- Owns everything ct does at the moment a Chaos Wastes run is CREATED: the
-- v0.7.95 starting-coins SETTER on both the setup_run argument and the
-- host-side rpc_deus_set_initial_soft_currency handler, the per-controller
-- progressive-difficulty base and the get_run_difficulty ramp that reads it,
-- every per-run ledger wiped at run start (altar reuse, the Chest-of-Trials
-- counter and its two rotation tables, the boon-altar no-repeat set, the
-- replacement and bot-economy caches), the run-start reporting (#487 freeze
-- breadcrumbs, the #467 price census, the #53 arena-node dump, the settings
-- dump and the host manifest baseline), and the boon roll whose no-repeat
-- ledger setup_run creates - DeusPowerUpUtils.generate_random_power_ups with
-- its count override, Bel'akor forced rarity, pool strip and post-roll
-- re-syncs. The three sibling loads the block interleaved with those hooks
-- (_ct_progressive_difficulty, _ct_replacement_runtime,
-- _ct_journey_difficulty_guard) travel with it so seven hook registrations
-- keep their order; each is still loaded exactly once.
--
-- Installed HERE, at the exact position the inline block occupied, so hook
-- registration order and _rt_register append order are unchanged: the
-- settings-dump block above it and the _ct_boon_offer_view_owner install below
-- it both keep their neighbours.
--
-- `_starting_coins_applied_for_run` is the one entry slot the moved chunk
-- WROTE. It stays a single entry local: the owner receives an accessor over it
-- so the run-start write and the inline starting_coins_value_matches_setting
-- check still address one slot. The three sync_ helpers are forward-declared
-- here and not filled until the boon-balance owner loads far below, so they
-- cross as late-binding wrappers.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner")(mod, {
    altar_reuse = _ct_altar_reuse,
    bomb_boon_names = BOMB_BOON_NAMES,
    build_local_manifest = _ct_peer_manifest.build_local_manifest,
    chest_default = CHEST_DEFAULT,
    dbg = function(...) return _dbg(...) end,
    dbg_alert = function(...) return _dbg_alert(...) end,
    effective_setting = effective_setting,
    log_peer_manifest = _ct_peer_manifest.log_peer_manifest,
    real_player_local_id = REAL_PLAYER_LOCAL_ID,
    rpc_schema = CT_RPC_SCHEMA,
    shrine_default = SHRINE_DEFAULT,
    starting_coins_applied_for_run = ctx.starting_coins_applied_for_run,
    sync_bomb_cooldown = function() return sync_bomb_cooldown() end,
    sync_boon_movespeed = function() return sync_boon_movespeed() end,
    sync_reckless_swings = function() return sync_reckless_swings() end,
})

-- ============================================================================
-- Boon-offer view LAYOUT -> _ct_boon_offer_view_owner.lua (#1159)
-- ============================================================================
-- Everything ct does to where the offered-boon widgets sit in the shrine
-- (DeusShopView) and the Chest of Trials (DeusCursedChestView) now lives in one
-- owner: the degenerate-arc NaN repair, the two build hooks, and the whole
-- _ct_boon_scroll block with its two per-frame `update` hooks. Installed HERE,
-- at the exact line the moved code occupied, so hook-registration order across
-- the whole mod is byte-for-byte what it was. WHICH boons get offered stays
-- above (generate_random_power_ups); what they COST stays with the pricing
-- modules; this owner only ever reads `#boon_widgets`.
-- `_dbg` crosses as a late-binding wrapper - it is the only entry local the
-- moved chunk closed over.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner")(mod, {
    dbg = function(...) return _dbg(...) end,
})

-- ============================================================
-- Node entry: curse runtime + node chest -> _ct_node_entry_owner.lua (#1159)
-- ============================================================
-- Owns everything ct does when the run moves INTO a Chaos Wastes node: whether
-- that node's curse activates (the MutatorHandler veto plus the node.curse
-- save-restore across _transition_next_node / start_next_round), how it is
-- displayed (get_current_node_curse, _enable_hover, and the two DeusThemeSettings
-- backfills that exist only because start_next_round forces theme="wastes" onto a
-- still-cursed node), the #470 curse-sorcerer rank-8 backfill that only matters
-- once a curse mutator has initialized, and whether that node's weapon chest can
-- produce a result at all (the deus_weapon_chest_distribution fallback keyed off
-- the SAME current-node walk, the altar-mix distribution shuffled off that node's
-- level_seed, the unknown-rarity strip on get_own_weapon_pool_excludes, and the
-- Trollhammer property-pool alias the upgrade chest reads).
--
-- Installed HERE, at the exact position the inline block occupied, so hook
-- registration order and _rt_register append order are unchanged: the offer-view
-- owner above it and the weapon-trait owner below it both keep their neighbours.
-- GENERATION-time curse filtering stays in _ct_campaign_graph_owner; this is the
-- runtime half, and the two share only the is_curse_disabled predicate the entry
-- still owns and passes to both.
--
-- `_defeat_recovery_triggered_this_round` is the one value the moved chunk WROTE.
-- It stays an entry local with exactly one storage slot: the owner receives the
-- same accessor closure _ct_combat_hooks already gets, so the reset at node
-- transition and the combat-side read/write still address one flag.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_node_entry_owner")(mod, {
    capture_returns = _capture_returns,
    dbg = function(...) return _dbg(...) end,
    defeat_recovery_triggered = ctx.defeat_recovery_triggered,
    effective_setting = effective_setting,
    is_curse_disabled = function(name) return is_curse_disabled(name) end,
    rt_register = _rt_register,
})

-- Weapon-trait pool mutation and the four generation hooks share one owner.
-- Install here to preserve the original hook and regression-check order.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_weapon_trait_generation")({
    mod = mod,
    effective_setting = effective_setting,
    dbg = _dbg,
    rt_register = _rt_register,
})

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
-- Pickup population pass + spawn census -> _ct_pickup_population_owner.lua (#1159)
-- ============================================================
-- Everything ct does at PickupSystem.populate_pickups now lives in one owner: the
-- per-mission BUDGET (altar / Chest-of-Trials / arena-ammo counts patched into
-- LevelSettings pickup_settings and restored around vanilla's call), the two pool
-- mutations that pass samples from (campaign-potion injection with full-group
-- renormalization, and the #143 Morgrim's grenade redistribution), the #58/#156
-- spawn census with its 8s delayed printf, the [ct-probe]/[populate_pickups]/
-- [ct:456] entry probes, and the #132 extensions_ready chest ground truth.
-- Installed HERE, at the exact line the moved code occupied, so hook-registration
-- order across the whole mod is byte-for-byte what it was.
--
-- WHAT materializes at one spawn seam stays with _ct_pickup_spawn_owner; WHETHER a
-- candidate may spawn at all stays with _ct_spawn_eligibility_owner. This owner
-- decides HOW MANY the mission gets, which pools are reachable while it gets them,
-- and counts what actually arrived.
--
-- Five ctx keys, five entry locals. `effective_setting` crosses as a late-binding
-- wrapper (assigned above this line today, but the wrapper survives the install
-- site moving). `_dump_pickup_system_state` / `_dump_pickup_spawners_verbose` MUST
-- cross as late-binding wrappers: their `function` bodies are assigned further DOWN
-- this file than this install site, so a by-value bind would freeze nil and both
-- post-populate dumps would silently no-op forever. The two career-exclusive
-- counters cross as SETTERS because the moved reset REASSIGNS them to fresh tables
-- and a module cannot assign another chunk's local.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_population_owner")(mod, {
    effective_setting            = function(...) return effective_setting(...) end,
    dump_pickup_system_state     = ctx.dump_pickup_system_state,
    dump_pickup_spawners_verbose = ctx.dump_pickup_spawners_verbose,
    set_career_exclusive_denial_counts   = ctx.set_career_exclusive_denial_counts,
    set_career_exclusive_logged_this_run = ctx.set_career_exclusive_logged_this_run,
})


    return {
        is_curse_disabled = is_curse_disabled,
    }
end
