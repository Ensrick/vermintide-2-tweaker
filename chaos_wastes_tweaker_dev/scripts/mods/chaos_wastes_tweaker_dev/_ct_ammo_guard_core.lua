-- Engine-free core for the ct_meta_ammo grant/clamp policy (issues 249 / 256 /
-- 289 evidence). Loaded via mod:dofile from _ct_meta_trait_boons.lua and via
-- loadfile from qa/lua/tests (no get_mod, no engine globals).
--
-- issue 249 / [ct:289] evidence: the meta-ammo stack buff was added through the
-- LOCAL BuffExtension.add_buff path inside the on_boon_granted proc, which only
-- ever landed stacks on the peer that ran the proc - a client audit showed
-- effective boons 5 with 0 active stacks while the host tracked correctly. The
-- fix makes the grant SERVER-AUTHORITATIVE: the host adds the stack through
-- BuffSystem.add_buff with is_server_controlled=true, which adds locally AND
-- broadcasts rpc_add_buff to every client [src: buff_system.lua:277-311], and
-- re-sends server-controlled buffs to hot-joining peers [src:
-- buff_system.lua:66-97]. grant_plan below is the pure decision kernel.

local M = {}

M.MARKER = "meta_ammo:server_authoritative_stack_grant_v0.7.298"

-- Decide how a peer must bring a player's meta-boon stack count up to target.
--   is_server:    is this peer the host (deletion/buff authority)?
--   wire_safe:    peer-parity confirmed (issue 426 gate; modded NetworkLookup
--                 indices may ride vanilla RPCs only when true)?
--   num_existing: stacks already on the unit's buff extension.
--   stacks_target: capped target stack count.
-- Returns (mode, n):
--   "none", 0            - already at/above target.
--   "defer_to_server", 0 - client peers never add; the host's server-controlled
--                          add replicates to them (issue 249 fix).
--   "networked", n       - host adds n stacks via BuffSystem server-controlled
--                          path (replicated + hot-join re-sent).
--   "local", n           - host adds n stacks via the local extension only
--                          (parity unconfirmed: zero wire exposure, host-only
--                          effect - the pre-fix behavior as fail-safe).
function M.grant_plan(is_server, wire_safe, num_existing, stacks_target)
    local have = type(num_existing) == "number" and num_existing or 0
    local want = type(stacks_target) == "number" and stacks_target or 0
    local n = want - have
    if n <= 0 then return "none", 0 end
    if not is_server then return "defer_to_server", 0 end
    if wire_safe then return "networked", n end
    return "local", n
end

-- issue 249 (restore half, 2026-08-16): after a [ct:426] parity degrade/restore
-- cycle the strip has broadcast removal of every server-controlled ct stack
-- buff, and any grant made while degraded used the LOCAL host-only fail-safe
-- path (grant_plan "local"). The restore callback re-injects only POOLS, so a
-- client ends the cycle holding its boons with ZERO stacks and the host's
-- num_existing (already at target from the local grants) makes every later
-- grant_plan delta 0 - the client can never converge. Decide the reconcile for
-- one (unit, stack template) on the host:
--   server_count: stacks added through the server-controlled (replicated) path
--                 and still tracked in BuffSystem.server_controlled_buffs.
--   local_total:  total stacks on the host's buff extension (server + local).
--   target:       capped stack target (current boon count).
-- Returns (remove_local_n, add_networked_n): remove remove_local_n host-only
-- stacks, then add add_networked_n through the server-controlled path so every
-- peer converges on exactly `target` replicated stacks.
M.RESTORE_MARKER = "ct249:parity_restore_stack_rebroadcast_v1"
function M.restore_plan(server_count, local_total, target)
    local sc = type(server_count) == "number" and server_count or 0
    local lt = type(local_total) == "number" and local_total or 0
    local tg = type(target) == "number" and target or 0
    local remove_local = lt - sc
    if remove_local < 0 then remove_local = 0 end
    local add_networked = tg - sc
    if add_networked < 0 then add_networked = 0 end
    return remove_local, add_networked
end

-- issue 256: clamp a current-value ammo field into [0, max]. Pure kernel behind
-- mod._ct_clamp_current_ammo_256 (the seam wrapper owns the printf).
-- Returns (clamped_value, changed).
function M.clamp_value(max_ammo, value)
    if type(value) ~= "number" then return value, false end
    local max = (type(max_ammo) == "number") and max_ammo or math.huge
    local clamped = math.max(0, math.min(value, max))
    return clamped, clamped ~= value
end

return M
