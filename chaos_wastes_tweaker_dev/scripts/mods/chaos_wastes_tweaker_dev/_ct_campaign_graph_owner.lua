--[[
_ct_campaign_graph_owner - Chaos Wastes journey-graph shaping (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns every ct decision that reshapes the GENERATED Chaos Wastes journey graph -
the deterministic structure the global `deus_populate_graph` returns once per
run, before any map UI, mission transition, or curse lookup reads it:
  * the exact cursed-mission count (CURSES_HOT_SPOTS_MIN/MAX_COUNT, the 0/0
    hot-spot range, the negative CURSES_MIN_PROGRESS floor) and the
    `disable_dominant_god` all-four-gods rotation, both applied to the vanilla
    config for the duration of the generator call and restored after it
  * the disabled-curse pool filter on config.AVAILABLE_CURSES (re-roll within
    the god rather than nil-curse the node) and its restore
  * the `replace_shrines_with_missions` SHOP -> TRAVEL base-graph conversion,
    done on a shallow per-node clone so the shared baked graph is never mutated
  * the #145 / #146 Citadel rewrite on the FINISHED graph: arena_citadel_* to
    finale_dominant_god, sig_citadel_* to finale_approach_god, with the curse
    re-matched deterministically from the synced level_seed
  * the three read-only probes those seams carry: #145 resolved-god census
    (host only), #56 Citadel curse host/client divergence, #136 all-node
    host/client divergence

Extracted VERBATIM from chaos_wastes_tweaker_dev.lua with no behaviour change.
The moved lines are byte-identical to the pre-extraction entry region; the only
additions are this header and the ctx binding block below. mod:dofile is not a
singleton - the entry calls it EXACTLY once, at the exact point this block used
to execute (after the DeusMapScene.on_enter hook, before the per-career weapon
override recovery), so hook-registration order and the load-time assignment of
the two CT_CITADEL145_* marker globals keep their original timing.

HOOKS OWNED (hooked EXACTLY ONCE in the whole mod - VMF silently drops a second
registration on the same pair):
  _G deus_populate_graph  (full hook, single-value return, both branches)
No other ct file hooks that global; grep-verified 2026-08-10.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
  * The graph-snapshot RPC transport stays in the ENTRY. This owner registers no
    network event, touches no chunk buffer, and neither reads nor writes the
    entry's mutable host-snapshot file-local; it only CALLS the host-side
    broadcast and the client-side apply at the two post-generator branches,
    exactly as the inline code did. The entry keeps its own late-arrival apply
    site (DeusMapScene.on_enter) and the live-run apply helper. Both absences are
    asserted mechanically by the owner test and by rt_textual_invariants, so the
    literal snapshot-state identifier must never appear in this file - not even
    in a comment, or the gate stops meaning anything.
  * _ct_curse_lighting_owner owns how a cursed node LOOKS once loaded; this file
    only decides which curse the node carries.
  * _ct_pickup_spawn_owner / _ct_spawn_eligibility_owner decide what spawns
    inside a mission; this file decides which missions exist at all.
  * The runtime curse-disable hooks (MutatorHandler._activate_mutator,
    DeusMechanism.get_current_node_curse / _transition_next_node /
    start_next_round, DeusMapDecisionView._enable_hover) stay in the entry. They
    are the generation-time filter's runtime counterpart: when a god's whole
    curse list is disabled this file deliberately leaves the vanilla list in
    place (an empty array crashes assign_random_curse) and those hooks null the
    picked curse instead. Splitting them apart is safe because they share no
    state - only the `is_curse_disabled` predicate, which the entry owns and
    hands to this module by value.

CROSS-FILE CONTRACT
Every entry file-local this block closed over is passed through ctx. Each one is
assigned EXACTLY ONCE and strictly before the entry's installer call, so binding
by value here resolves to the identical function/table object the inline code
saw - none is a forward slot that gets replaced later, so no late-binding
accessor is needed (contrast _cim_weave_loadout_owner's _bubble_cap):
  ctx.dbg                      entry :99   local function, single definition
  ctx.effective_setting        entry :2631 forward slot :785, assigned once
  ctx.is_curse_disabled        entry :2778 forward slot :779, assigned once
  ctx.finale_gods              entry :648  constant array, never reassigned
  ctx.apply_graph_snapshot     entry :2223 local function, single definition
  ctx.broadcast_graph_snapshot entry :2369 local function, single definition
The asserts below turn a dropped ctx key into a load-time failure instead of a
nil call at graph generation, which on a client would surface only as silent
host/client map divergence in a live multiplayer run.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_campaign_graph_owner.lua,
qa/lua/tests/test_ct_entry_decomposition.lua, and the #145 rt_textual_invariants
row that pins mod._ct_force_finale_god to BOTH deus_populate_graph branches.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_campaign_graph_owner requires a context table")
assert(type(ctx.dbg) == "function", "_ct_campaign_graph_owner requires ctx.dbg")
assert(type(ctx.effective_setting) == "function", "_ct_campaign_graph_owner requires ctx.effective_setting")
assert(type(ctx.is_curse_disabled) == "function", "_ct_campaign_graph_owner requires ctx.is_curse_disabled")
assert(type(ctx.finale_gods) == "table" and #ctx.finale_gods == 4,
    "_ct_campaign_graph_owner requires ctx.finale_gods (the four-entry god array)")
assert(type(ctx.apply_graph_snapshot) == "function", "_ct_campaign_graph_owner requires ctx.apply_graph_snapshot")
assert(type(ctx.broadcast_graph_snapshot) == "function", "_ct_campaign_graph_owner requires ctx.broadcast_graph_snapshot")

local _dbg                     = ctx.dbg
local effective_setting        = ctx.effective_setting
local is_curse_disabled        = ctx.is_curse_disabled
local FINALE_GODS              = ctx.finale_gods
local apply_graph_snapshot     = ctx.apply_graph_snapshot
local broadcast_graph_snapshot = ctx.broadcast_graph_snapshot

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
end

return install
