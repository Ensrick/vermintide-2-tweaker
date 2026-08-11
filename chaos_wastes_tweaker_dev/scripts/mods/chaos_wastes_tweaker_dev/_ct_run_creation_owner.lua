--[[
_ct_run_creation_owner - the RUN-CREATION seam (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns everything ct does at the moment a Chaos Wastes run is CREATED, plus the
one roll whose per-run state that creation resets, and nothing else. Every
branch below is reachable only from DeusRunController.setup_run or from state
that setup_run alone establishes:

  * WHAT DIFFICULTY THE RUN RAMPS TO. setup_run captures the run's TRUE starting
    tier onto the controller instance (or takes the hot-join value the policy's
    RPC parked on `mod._ct_progdiff_pending_host_start`), and
    DeusRunController.get_run_difficulty reads that base back on every mission to
    apply the #460 step-on-maps-3-and-5 ramp. The two are one mechanism: the ramp
    is meaningless without the per-controller base, and the base is dead state
    without the ramp. The tier arithmetic itself - including the dynamic
    Cataclysm ceiling - stays in the _ct_progressive_difficulty policy this owner
    loads; only the capture, the hook and the throttled `[ct:progdiff]` line live
    here.

  * WHAT THE RUN STARTS WITH. The v0.7.95 starting-coins SETTER: setup_run
    rewrites vanilla's `initial_own_soft_currency` argument (args[5]) BEFORE
    vanilla's own set_player_soft_currency runs, so a configured value is an
    exact total and never an addition on top of rollover. The host-side
    DeusRunController.rpc_deus_set_initial_soft_currency handler enforces the
    same host setting on a joining client's row - the belt-and-suspenders half of
    the same fix, which is why both sit in one file.

  * WHAT THE RUN RESETS. Every per-run ledger wiped at run start: the altar reuse
    counts (through the _ct_altar_reuse owner's exported rebind), the
    Chest-of-Trials per-mission counter and the two #117 / #463 rotation tables,
    the boon-altar no-repeat taken set, the replacement-compensation caches, and
    the bot-economy init/log state.

  * WHAT THE RUN REPORTS. The #487 freeze breadcrumbs bracketing vanilla's
    deus_generate_graph -> deus_populate_graph solve, the #467 one-shot boon price
    census, the #53 post-populate arena-node graph dump, the host-authoritative
    settings dump, and the host's own peer manifest baseline. The transports those
    last two ride (settings-sync, graph-snapshot, peer-manifest) stay entry
    file-locals; this owner only CALLS them.

  * WHICH BOONS THE ROLL CAN OFFER. DeusPowerUpUtils.generate_random_power_ups is
    here because the boon-altar no-repeat set it filters against is a per-run
    ledger setup_run creates, and because the shared `mod._ct_boon_disabled`
    predicate its pool strip defines is the same one the grant choke point reads.
    The hook owns the shrine/chest count override, the Bel'akor temple
    forced-rarity write with its #134 arity extension, the remove-then-restore
    pool strip (disabled boons, bomb-boon exclusivity, altar no-repeat), and the
    post-roll re-syncs (Khaine's Fury, bomb cooldown, boon movespeed, the #130
    lazy parry-cooldown strip). WHERE the resulting widgets sit is
    _ct_boon_offer_view_owner's; what they COST is the pricing modules'.

EXTRACTION
ONE contiguous chunk moved: entry lines 2210-2709 (500 raw / 466 non-empty
lines), MD5 e0b45d545562537671135c60e7882085 over the pristine `git archive`
bytes. Every line is byte-identical to the pre-extraction entry region with
exactly ONE deviation (below). The only additions are this header, the ctx
binding block, and the closing `end` / `return install`. `mod:dofile` is not a
singleton, so the entry calls this installer EXACTLY once, at the exact line the
moved block occupied - after the umbrella / settings-dump block above it and
immediately before the _ct_boon_offer_view_owner install below it - so hook
registration order and _rt_register append order are unchanged mod-wide.

The moved chunk itself loads three sibling modules (_ct_progressive_difficulty,
_ct_replacement_runtime, _ct_journey_difficulty_guard) because those three loads
were interleaved BETWEEN the hooks above and the setup_run hook below, and
splitting them out would have reordered seven hook registrations. Each is still
loaded exactly once, from exactly one place, at the same point in the load
sequence - one stack frame deeper. None of the three registers a regression
check, so /ct_regression_test output order is untouched. This mirrors
_ct_chest_revive_owner, which carries its own `mod._ct_chest_revive_policy` load
for the same reason.

THE ONE DEVIATION
The starting-coins hook recorded which run its setter fired for by assigning the
entry local `_starting_coins_applied_for_run`. That local is BOTH written here
and read by the `starting_coins_value_matches_setting` regression check, which
deliberately stays INLINE in the entry (moving the check would freeze its read at
the dofile-time nil - the dropped-upvalue burn class - silently turning a runtime
verify into a permanent no-op PASS). Re-declaring the local at this module's scope
would split one slot into two that never agree, producing exactly that failure
from the other direction. The line therefore becomes a call to an accessor over
the SAME entry slot, injected as ctx.starting_coins_applied_for_run:

    _starting_coins_applied_for_run = run_id   ->   starting_coins_applied_for_run(run_id)

The declaration and the reader both stay in the entry, so there is still exactly
one slot. Because a silently-broken accessor would make that inline check a
permanent no-op PASS rather than a FAIL, the substitution carries a positive
control: `qa/lua/tests/test_ct_run_creation_owner.lua` installs against a
recording accessor and asserts setup_run drives it to the live run id, and drives
the same setup_run with the accessor mutated to a no-op to prove the assertion
can fail (PROJECT_STANDARDS.md 5.1d rule 2).

CROSSINGS
Fifteen entry values cross, one of them state:
  * `_starting_coins_applied_for_run` crosses as the ACCESSOR above - the only
    entry slot this chunk writes.
  * `_dbg`, `_dbg_alert`, `sync_reckless_swings`, `sync_bomb_cooldown` and
    `sync_boon_movespeed` cross as WRAPPER CLOSURES. The three sync_ slots are
    forward-declared in the entry and not filled until the boon-balance owner
    loads ~2400 lines BELOW this install point, so a by-value capture here would
    freeze nil into every post-roll re-sync; the two debug helpers use the same
    form as the adjacent _ct_boon_offer_view_owner and _ct_node_entry_owner
    installs.
  * `effective_setting`, `_ct_altar_reuse`, `_build_local_manifest`,
    `_log_peer_manifest`, `BOMB_BOON_NAMES`, `SHRINE_DEFAULT`, `CHEST_DEFAULT`,
    `REAL_PLAYER_LOCAL_ID` and `CT_RPC_SCHEMA` cross BY VALUE. All nine are
    already assigned above this install point and none is ever reassigned - the
    same by-value form the _ct_node_entry_owner install below uses.
Each ctx binding keeps the entry's own identifier name, so every call site in the
moved chunk is byte-identical to what it was.

Game globals (Managers, DeusPowerUpsArray, DeusPowerUpsArrayByRarity,
DeusPowerUpAvailabilityTypes, Difficulties, DifficultyLookup, printf, unpack)
stay late-bound inside the callbacks exactly as before, and
CT_PROGRESSIVE_DIFFICULTY_MARKER is still assigned as a global at the same load
point, so the _ct_regression.lua check that reads it is unaffected.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Consumed via: mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner")(mod, ctx)
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_run_creation_owner requires a context table")
assert(type(ctx.dbg) == "function",
    "_ct_run_creation_owner requires ctx.dbg")
assert(type(ctx.dbg_alert) == "function",
    "_ct_run_creation_owner requires ctx.dbg_alert")
assert(type(ctx.effective_setting) == "function",
    "_ct_run_creation_owner requires ctx.effective_setting")
-- reset_uses is asserted too, not just the table: it is called once per RUN, so
-- a table that lost the export would crash mid-run instead of failing at load.
assert(type(ctx.altar_reuse) == "table" and type(ctx.altar_reuse.reset_uses) == "function",
    "_ct_run_creation_owner requires ctx.altar_reuse with a reset_uses export")
assert(type(ctx.build_local_manifest) == "function",
    "_ct_run_creation_owner requires ctx.build_local_manifest")
assert(type(ctx.log_peer_manifest) == "function",
    "_ct_run_creation_owner requires ctx.log_peer_manifest")
assert(type(ctx.starting_coins_applied_for_run) == "function",
    "_ct_run_creation_owner requires ctx.starting_coins_applied_for_run")
assert(type(ctx.sync_reckless_swings) == "function",
    "_ct_run_creation_owner requires ctx.sync_reckless_swings")
assert(type(ctx.sync_bomb_cooldown) == "function",
    "_ct_run_creation_owner requires ctx.sync_bomb_cooldown")
assert(type(ctx.sync_boon_movespeed) == "function",
    "_ct_run_creation_owner requires ctx.sync_boon_movespeed")
assert(type(ctx.bomb_boon_names) == "table",
    "_ct_run_creation_owner requires ctx.bomb_boon_names")
assert(type(ctx.shrine_default) == "number",
    "_ct_run_creation_owner requires ctx.shrine_default")
assert(type(ctx.chest_default) == "number",
    "_ct_run_creation_owner requires ctx.chest_default")
assert(type(ctx.real_player_local_id) == "number",
    "_ct_run_creation_owner requires ctx.real_player_local_id")
assert(type(ctx.rpc_schema) == "number",
    "_ct_run_creation_owner requires ctx.rpc_schema")

-- Each binding keeps the entry's identifier so the moved chunk below reads
-- byte-identically to the region it came from.
local _dbg = ctx.dbg
local _dbg_alert = ctx.dbg_alert
local effective_setting = ctx.effective_setting
local _ct_altar_reuse = ctx.altar_reuse
local _build_local_manifest = ctx.build_local_manifest
local _log_peer_manifest = ctx.log_peer_manifest
local BOMB_BOON_NAMES = ctx.bomb_boon_names
local SHRINE_DEFAULT = ctx.shrine_default
local CHEST_DEFAULT = ctx.chest_default
local REAL_PLAYER_LOCAL_ID = ctx.real_player_local_id
local CT_RPC_SCHEMA = ctx.rpc_schema
local sync_reckless_swings = ctx.sync_reckless_swings
local sync_bomb_cooldown = ctx.sync_bomb_cooldown
local sync_boon_movespeed = ctx.sync_boon_movespeed
-- THE ONE DEVIATION (see header): the accessor over the entry's single
-- `_starting_coins_applied_for_run` slot, which the inline
-- starting_coins_value_matches_setting check still reads as an upvalue.
local starting_coins_applied_for_run = ctx.starting_coins_applied_for_run

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
-- configured Starting Coins value is valid, replace arg[5] before vanilla.
-- Zero is a real configured value, not a sentinel for rollover. Vanilla's
-- setter (deus_run_controller.lua:315) therefore writes exactly 0..3000.
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
-- setup_run receives the original tier during an ordinary start; the installed
-- adapter supplies it for hot joins. Keep it on the controller instance so an
-- overlapping/replaced controller cannot leak ramp state into a later run.
CT_PROGRESSIVE_DIFFICULTY_MARKER = "progressive_difficulty:per_controller_start_hotjoin_sync_contiguous_tiers_v3"
mod._ct_progressive_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_difficulty")
mod._ct_progressive_policy.install_hot_join(mod, CT_RPC_SCHEMA)
mod._ct_progdiff_step = function(start_key, completed_level_count)
    local Diff = rawget(_G, "Difficulties")
    local Lookup = rawget(_G, "DifficultyLookup")
    return mod._ct_progressive_policy.difficulty(start_key, completed_level_count, Diff, Lookup)
end

mod:hook("DeusRunController", "get_run_difficulty", function(func, self)
    local base = func(self)
    if not effective_setting("progressive_difficulty")
        or not effective_setting("progressive_difficulty_increase") then return base end
    local start_key = (self and self._ct_progdiff_start) or base
    local run_state = self and self._run_state
    local completed = (run_state and run_state.get_completed_level_count
        and run_state:get_completed_level_count()) or 0
    local stepped = mod._ct_progdiff_step(start_key, completed)
    if completed ~= self._ct_progdiff_last_logged then
        self._ct_progdiff_last_logged = completed
        pcall(printf, "[ct:progdiff] mission %d (completed=%d): start=%s -> difficulty=%s",
            completed + 1, completed, tostring(start_key), tostring(stepped))
    end
    return stepped
end)

-- Replacement-player progression compensation (Issue #465). Runtime ownership
-- is extracted to keep the CT entry chunk below its frozen decomposition ceiling.
mod._ct_replacement_runtime = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_runtime")
mod._ct_replacement_runtime.install(mod, {
    effective_setting = effective_setting,
    real_player_local_id = REAL_PLAYER_LOCAL_ID,
})
-- Journey-completion difficulty guard owner (#291 / #1159).
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_journey_difficulty_guard")(mod)

mod:hook("DeusRunController", "setup_run", function(func, self, ...)
    -- STARTING_COINS_MODE_MARKER = exact-total-including-zero-v2
    -- v0.7.127-dev: reset altar reuse counts at run start. Previous-run go_ids
    -- can collide with this run's new chests if Stingray's unit_storage cycles
    -- the same network ids; wiping at run start avoids ghost-use counts.
    -- #1159: the ledger moved into _ct_altar_reuse_owner with every one of its
    -- readers, so the wipe is the owner's exported rebind of the same local.
    _ct_altar_reuse.reset_uses()
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
    if mod._ct919_log_profile_snapshot then mod._ct919_log_profile_snapshot("setup_run") end
    -- Progressive Difficulty: capture this run's TRUE starting difficulty (the
    -- setup_run `difficulty` arg = args[2]) so the get_run_difficulty ramp computes
    -- from a stable base, and reset the per-mission log throttle. At run start this is
    -- the unstepped base on every peer present (step==0 at completed==0).
    self._ct_progdiff_start = mod._ct_progdiff_pending_host_start or args[2]
    mod._ct_progdiff_pending_host_start = nil
    self._ct_progdiff_last_logged = nil
    self._ct_progcoin_last_logged = nil
    mod._ct_replacement_cache = {}
    mod._ct_replacement_pending_humans = {}
    mod._ct_replacement_log_count = 0
    mod._ct_bot_economy_initialized = {}
    mod._ct_bot_economy_log_count = 0
    -- Vanilla signature: (run_seed, difficulty, journey_name, dominant_god,
    -- initial_own_soft_currency, telemetry_id, with_belakor, mutators, boons)
    -- so initial_own_soft_currency is args[5].
    -- effective_setting reads host's broadcast value on clients and own value on host,
    -- so both peers compute the same target. The host-side RPC handler enforces it again.
    local run_state = self and self._run_state
    local run_id = run_state and run_state.get_run_id and run_state:get_run_id() or "unknown"
    local vanilla_initial = args[5]
    local setting, configured = mod._ct_starting_coins_policy.resolve(
        effective_setting("starting_coins"), vanilla_initial)

    if configured then
        args[5] = setting
        starting_coins_applied_for_run(run_id)
        _dbg("[ct/coins] starting_coins setter applied: vanilla_initial=%s, setting=%d, final=%d (run_id=%s)",
            tostring(vanilla_initial), setting, setting, tostring(run_id))
    else
        _dbg_alert("[ct:912] invalid Starting Coins value; preserving vanilla_initial=%s",
            tostring(vanilla_initial))
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
-- BEFORE vanilla computes `new_coins`. Zero is an exact baseline; vanilla's
-- separate progress compensation remains added for a genuine mid-run join.
mod:hook("DeusRunController", "rpc_deus_set_initial_soft_currency", function(func, self, sender_channel_id, initial_own_soft_currency)
    local host_setting, configured = mod._ct_starting_coins_policy.resolve(
        mod:get("starting_coins"), initial_own_soft_currency)
    if configured then
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
    -- opens it). The strip body is idempotent — registered cooldown durations
    -- already at zero are left untouched (#342). Safe to call from every roll.
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

end

return install
