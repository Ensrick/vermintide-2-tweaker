-- _gut_bot_pose.lua — Restore the is_bot argument omitted by PlayerBot.spawn for slot_pose (#232).
--
-- Vanilla PlayerBot.spawn passes is_bot to the slot_skin/slot_frame lookups
-- (player_bot.lua:134/:137) but OMITS it for slot_pose (player_bot.lua:142),
-- so a bot podium pose always resolves from the HUMAN loadout. The repair
-- owns a spawn-depth context (PlayerBot.spawn hook) and forwards is_bot=true
-- to BackendUtils.get_loadout_item (backend_utils.lua:30, signature
-- career_name/slot/is_bot) only for a nil-is_bot slot_pose lookup made inside
-- that context. Pure decision logic lives in _gut_bot_pose_policy.lua.
--
-- The hook callbacks are NAMED locals registered once each (VMF drops a second
-- hook on the same (Class, method) pair) and exported via the returned api, so
-- the issue232 runtime check and the offline harness both EXECUTE the exact
-- registered function objects (composed the way VMF composes them:
-- callback(next_fn, <original call args>), mod_shim.lua:108-109) instead of
-- observing registration booleans.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_bot_pose_policy")
local player_bot = rawget(_G, "PlayerBot")
local backend_utils = rawget(_G, "BackendUtils")
local _unpack = unpack
local spawn_depth = 0
local repaired_count = 0
local logged_careers = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function traceback(err)
    local dbg = rawget(_G, "debug")
    return dbg and dbg.traceback and dbg.traceback(tostring(err), 2) or tostring(err)
end

-- PlayerBot.spawn hook callback: owns the bounded synchronous spawn context.
-- Depth is restored on EVERY exit path (xpcall unwind) so a throw inside
-- vanilla spawn can never leave the repair latched for later human lookups.
local function _spawn_cb(func, self, ...)
    local args = pack(...)
    spawn_depth = spawn_depth + 1
    local result = pack(xpcall(function()
        return func(self, _unpack(args, 1, args.n))
    end, traceback))
    spawn_depth = math.max(spawn_depth - 1, 0)
    if not result[1] then
        error(result[2], 0)
    end
    return _unpack(result, 2, result.n)
end

-- BackendUtils.get_loadout_item hook callback: delegates the is_bot decision
-- to the pure policy and forwards positionally (career_name, slot, resolved,
-- ...) exactly as vanilla's signature expects (backend_utils.lua:30).
local function _lookup_cb(func, career_name, slot_name, is_bot, ...)
    local resolved, repaired = Policy.resolve_is_bot(spawn_depth, slot_name, is_bot)
    if repaired then
        repaired_count = repaired_count + 1
        if not logged_careers[career_name] then
            logged_careers[career_name] = true
            mod:info("[gut:232] career=%s slot=slot_pose is_bot=true repaired=%d",
                tostring(career_name), repaired_count)
        end
    end
    return func(career_name, slot_name, resolved, ...)
end

local spawn_hooked = false
if player_bot and type(player_bot.spawn) == "function" then
    mod:hook(player_bot, "spawn", _spawn_cb)
    spawn_hooked = true
end

local lookup_hooked = false
if backend_utils and type(backend_utils.get_loadout_item) == "function" then
    mod:hook(backend_utils, "get_loadout_item", _lookup_cb)
    lookup_hooked = true
end

-- Execute the registered hook chain against fake delegates (no engine calls,
-- no real spawn): a fake PlayerBot.spawn body runs through _spawn_cb and its
-- backend lookups run through _lookup_cb, asserting the delegate RECEIVES the
-- repaired argument only inside the bot spawn context. Synchronous and
-- self-restoring: spawn_depth returns to its entry value on every path, so
-- running this from the regression command cannot perturb live state. The
-- probe career name is synthetic so the per-career [gut:232] receipt dedup for
-- real careers is untouched.
local function _exec_chain_cases()
    local seen = {}
    local function probe(career_name, slot_name, is_bot, ...)
        seen = { career = career_name, slot = slot_name, is_bot = is_bot,
            extra_n = select("#", ...), extra1 = (select("#", ...) > 0) and (select(1, ...)) or nil }
        return "item_" .. tostring(is_bot)
    end
    local career = "gut_rt232_probe"

    -- 1. Bot spawn context: vanilla's 2-arg pose lookup (player_bot.lua:142
    --    omits is_bot) must reach the backend delegate with is_bot=true.
    local item
    local r1, r2, r3 = _spawn_cb(function(self)
        item = _lookup_cb(probe, career, "slot_pose", nil)
        return "unit", nil, 3
    end, {})
    if seen.is_bot ~= true or seen.career ~= career or seen.slot ~= "slot_pose" then
        return "bot spawn pose lookup did not deliver is_bot=true to the backend delegate"
    end
    if item ~= "item_true" then
        return "repaired lookup result was not forwarded back to the spawn body"
    end
    if r1 ~= "unit" or r2 ~= nil or r3 ~= 3 then
        return "spawn hook did not pass through the spawn return values"
    end

    -- 2. Outside any spawn: the same lookup stays untouched (human path).
    _lookup_cb(probe, career, "slot_pose", nil)
    if seen.is_bot ~= nil then
        return "human pose lookup was modified outside the spawn context"
    end

    -- 3. Explicit flag and non-pose slots inside the spawn stay untouched;
    --    trailing varargs are forwarded positionally.
    _spawn_cb(function()
        _lookup_cb(probe, career, "slot_pose", false)
        if seen.is_bot ~= false then return end
        _lookup_cb(probe, career, "slot_skin", nil, "extra_arg")
    end, {})
    if seen.slot ~= "slot_skin" or seen.is_bot ~= nil then
        return "explicit-flag or non-pose lookup was modified inside the spawn context"
    end
    if seen.extra_n ~= 1 or seen.extra1 ~= "extra_arg" then
        return "trailing lookup arguments were not forwarded"
    end

    -- 4. Nested spawn keeps the repair active at depth 2 and fully unwinds.
    _spawn_cb(function()
        _spawn_cb(function()
            _lookup_cb(probe, career, "slot_pose", nil)
        end, {})
    end, {})
    if seen.is_bot ~= true then
        return "nested spawn context lost the repair"
    end
    _lookup_cb(probe, career, "slot_pose", nil)
    if seen.is_bot ~= nil then
        return "spawn depth did not unwind after nested spawns"
    end

    -- 5. Error unwind: a throwing spawn body propagates its error AND restores
    --    the depth so later human lookups stay untouched.
    local ok, err = pcall(_spawn_cb, function()
        error("gut_rt232_boom")
    end, {})
    if ok or not tostring(err):find("gut_rt232_boom", 1, true) then
        return "spawn hook swallowed or replaced the spawn error"
    end
    _lookup_cb(probe, career, "slot_pose", nil)
    if seen.is_bot ~= nil then
        return "spawn depth leaked after an error unwind"
    end
    return nil
end

return {
    policy = Policy,
    hook_callbacks = { spawn = _spawn_cb, lookup = _lookup_cb },
    exec_chain_cases = _exec_chain_cases,
    rt_checks = {
        {
            name = "issue232_bot_designated_victory_pose",
            fn = function()
                if not spawn_hooked then return "PlayerBot.spawn hook missing" end
                if not lookup_hooked then return "BackendUtils.get_loadout_item hook missing" end
                return _exec_chain_cases()
            end,
        },
    },
}
