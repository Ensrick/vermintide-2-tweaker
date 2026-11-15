-- _gt_world.lua - the one owner of "is the level world alive" and "where is
-- this unit" for gt_dev draw and spawn paths (WP-GT-03, audit finding A6-F08).
--
-- WorldManager.world(name) asserts when the world is missing; has_world is the
-- safe probe (Vermintide-2-Source-Code/foundation/scripts/managers/world/world_manager.lua:107-115).
-- A handle cached from a destroyed world is a native fault that pcall cannot
-- catch, and mod.update keeps running between game states, when no level world
-- exists. POSITION_LOOKUP[unit] is a dead handle in mod.update and chat-command
-- context; Unit.world_position(unit, 0) is the safe read.
-- Engine-free: the engine tables come in through `new` so the offline suite can
-- drive it (qa/lua/tests/test_gt_world.lua).
local M = {}

function M.new(engine)                       -- engine = { managers = function() return Managers end, Unit = Unit }
    local W = {}
    function W.live()
        local managers = engine.managers()
        local wm = managers and managers.world
        if not (wm and wm:has_world("level_world")) then return nil end
        return wm:world("level_world")
    end
    function W.is_live(world)
        return world ~= nil and W.live() == world
    end
    function W.unit_pos(unit)
        if not (unit and engine.Unit.alive(unit)) then return nil end
        return engine.Unit.world_position(unit, 0)
    end
    return W
end

return M
