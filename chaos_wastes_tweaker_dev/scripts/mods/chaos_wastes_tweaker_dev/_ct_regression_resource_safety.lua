-- _ct_regression_resource_safety.lua - late resource-safety regression checks for CT Dev
--
-- Owns the final ten /ct_regression_test registrations in their frozen order:
-- generated localization, forward-reference and call-shape safety, mutation
-- restoration, paced transport, server-authoritative ammo, and cursed-chest
-- reconciliation. The parent loads this pure installer before registering any
-- check and invokes it only at the suite's original tail position.
--
-- Owned by: _ct_regression.lua. Consumed via:
-- scripts/mods/chaos_wastes_tweaker_dev/_ct_regression_resource_safety

return function(mod, ctx)
assert(type(mod) == "table", "CT resource-safety regression mod is required")
assert(type(ctx) == "table", "CT resource-safety regression context must be a table")
assert(type(mod._ct_rt_register) == "function",
    "CT resource-safety regression registrar is required")

local _rt_register = mod._ct_rt_register
local _dump_pickup_system_state = ctx.dump_pickup_system_state
local _dump_pickup_spawners_verbose = ctx.dump_pickup_spawners_verbose
local CT_VARIADIC_ARITY_MARKER = ctx.variadic_arity_marker
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

_rt_register("ct_meta_ammo_server_auth_grant_249", function()
    -- v0.7.298-dev (issues 249/289): the meta-boon stack grant must be
    -- server-authoritative (host adds via BuffSystem server-controlled path,
    -- clients defer to replication) and parity-gated (issue 426). Drives the
    -- pure grant_plan kernel through the exact decision matrix.
    local core = mod._ct_ammo_guard_core
    if type(core) ~= "table" or type(core.grant_plan) ~= "function" then
        return "#249 REGRESSION: mod._ct_ammo_guard_core.grant_plan missing (server-auth grant reverted?)"
    end
    if CT_META_AMMO_SERVER_AUTH_MARKER ~= "meta_ammo:server_authoritative_stack_grant_v0.7.298" then
        return "#249 REGRESSION: CT_META_AMMO_SERVER_AUTH_MARKER missing/mismatch; got " .. tostring(CT_META_AMMO_SERVER_AUTH_MARKER)
    end
    if type(mod._ct_wire_safe) ~= "function" then
        return "#249 REGRESSION: mod._ct_wire_safe parity gate missing (issue 426 beacon not installed)"
    end
    local cases = {
        -- is_server, wire_safe, existing, target, want_mode, want_n
        { true,  true,  0, 5, "networked", 5 },
        { true,  true,  3, 5, "networked", 2 },
        { true,  false, 0, 5, "local",     5 },
        { false, true,  0, 5, "defer_to_server", 0 },
        { false, false, 2, 5, "defer_to_server", 0 },
        { true,  true,  5, 5, "none", 0 },
        { true,  true,  7, 5, "none", 0 },
        { false, true,  5, 5, "none", 0 },
    }
    for i, c in ipairs(cases) do
        local mode, n = core.grant_plan(c[1], c[2], c[3], c[4])
        if mode ~= c[5] or n ~= c[6] then
            return string.format("#249 REGRESSION: grant_plan case %d gave (%s,%s), expected (%s,%d)",
                i, tostring(mode), tostring(n), c[5], c[6])
        end
    end
end)

_rt_register("cursed_chest_reconcile_132", function()
    -- v0.7.298-dev (issues 132/60): the settled chest reconcile must exist
    -- (prune-side cross-path cap) with its pickup-path ledger feed, and the
    -- pure planner must never prune below cap, outside the pickup set, or on a
    -- non-prunable (non-WAITING) chest.
    local m132 = mod._ct_chest132
    if type(m132) ~= "table" or type(m132.pickup_chest) ~= "function" then
        return "#132 REGRESSION: mod._ct_chest132.pickup_chest ledger feed missing"
    end
    if m132.RECONCILE_MARKER ~= "CT_CHEST132_RECONCILE_PRUNE_v0.7.298" then
        return "#132 REGRESSION: RECONCILE_MARKER missing/mismatch; got " .. tostring(m132.RECONCILE_MARKER)
    end
    local core = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_count_audit_core")
    if type(core) ~= "table" or type(core.reconcile_plan) ~= "function" then
        return "#132 REGRESSION: _ct_chest_count_audit_core.reconcile_plan missing"
    end
    local u1, u2, u3, u4, u5 = "u1", "u2", "u3", "u4", "u5"
    local appearance = { u1, u2, u3, u4, u5 }
    local pickup_set = { [u3] = true, [u4] = true, [u5] = true }
    local alive = function() return true end
    local waiting = function(u) return u ~= u5 end  -- u5 already activated
    local plan = core.reconcile_plan(appearance, pickup_set, 3, alive, waiting)
    if plan.alive_n ~= 5 or plan.over_n ~= 2 then
        return string.format("#132 REGRESSION: plan counts wrong (alive=%s over=%s, expected 5/2)",
            tostring(plan.alive_n), tostring(plan.over_n))
    end
    -- Excess 2: u5 blocked (non-WAITING), u4 + u3 prunable from the end.
    if #plan.prune ~= 2 or plan.prune[1] ~= u4 or plan.prune[2] ~= u3 or plan.unprunable_n ~= 0 then
        return string.format("#132 REGRESSION: prune selection wrong (%s,%s unprunable=%s; expected u4,u3/0)",
            tostring(plan.prune[1]), tostring(plan.prune[2]), tostring(plan.unprunable_n))
    end
    -- Baked-only over-cap (nothing in the pickup set) must prune NOTHING.
    local baked_plan = core.reconcile_plan({ u1, u2 }, {}, 1, alive, waiting)
    if #baked_plan.prune ~= 0 or baked_plan.unprunable_n ~= 1 then
        return "#132 REGRESSION: baked-only over-cap must be reported unprunable, never deleted"
    end
    -- Under-cap must be a full no-op plan.
    local under = core.reconcile_plan({ u1 }, { [u1] = true }, 3, alive, waiting)
    if #under.prune ~= 0 or under.over_n ~= 0 then
        return "#132 REGRESSION: under-cap mission produced a prune plan"
    end
end)
end
