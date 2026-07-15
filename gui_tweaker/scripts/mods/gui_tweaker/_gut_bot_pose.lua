-- Restore the is_bot argument omitted by PlayerBot.spawn for slot_pose (#232).
local mod = get_mod("gut")
local Policy = mod:dofile("scripts/mods/gui_tweaker/_gut_bot_pose_policy")
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

local spawn_hooked = false
if player_bot and type(player_bot.spawn) == "function" then
    mod:hook(player_bot, "spawn", function(func, self, ...)
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
    end)
    spawn_hooked = true
end

local lookup_hooked = false
if backend_utils and type(backend_utils.get_loadout_item) == "function" then
    mod:hook(backend_utils, "get_loadout_item",
        function(func, career_name, slot_name, is_bot, ...)
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
        end)
    lookup_hooked = true
end

return {
    policy = Policy,
    rt_checks = {
        {
            name = "issue232_bot_designated_victory_pose",
            fn = function()
                if not spawn_hooked then return "PlayerBot.spawn hook missing" end
                if not lookup_hooked then return "BackendUtils.get_loadout_item hook missing" end
                local resolved, repaired = Policy.resolve_is_bot(1, "slot_pose", nil)
                if resolved ~= true or repaired ~= true then
                    return "bot pose argument repair policy failed"
                end
                local human, touched = Policy.resolve_is_bot(0, "slot_pose", nil)
                if human ~= nil or touched then
                    return "human pose lookup was modified"
                end
                return nil
            end,
        },
    },
}
