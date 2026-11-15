-- WP-GT-03 (audit finding A6-F08): one module owns "is the level world alive"
-- and "where is this unit". WorldManager.world(name) asserts when the world is
-- missing and has_world is the safe probe
-- (Vermintide-2-Source-Code/foundation/scripts/managers/world/world_manager.lua:107-115);
-- a handle cached from a destroyed world is a native fault pcall cannot catch.
return function(H, repo_root)
    local folder = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local function read(name)
        local file = assert(io.open(folder .. name, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local World = dofile(folder .. "_gt_world.lua")

    local function stub(state)
        local wm = {}
        function wm:has_world(name) return name == "level_world" and state.world ~= nil end
        function wm:world(name)
            if name ~= "level_world" or state.world == nil then error("world " .. tostring(name) .. " not found") end
            return state.world
        end
        local positions = 0
        local unit_api = {
            alive = function(unit) return unit ~= nil and unit.alive ~= false end,
            world_position = function(unit, node)
                positions = positions + 1
                return { unit = unit, node = node }
            end,
        }
        local W = World.new({
            managers = function()
                if state.no_managers then return nil end
                if state.no_world_manager then return {} end
                return { world = wm }
            end,
            Unit = unit_api,
        })
        return W, function() return positions end
    end

    H.test("GT A6-F08 live() is nil, without raising, when the level world is missing", function()
        local W = stub({ world = nil })
        local ok, value = pcall(W.live)
        H.equal(ok, true, "live() must not raise")
        H.equal(value, nil)
    end)

    H.test("GT A6-F08 live() returns the level world when present", function()
        local w1 = { name = "w1" }
        local W = stub({ world = w1 })
        H.equal(W.live(), w1)
    end)

    H.test("GT A6-F08 is_live() follows the current world identity", function()
        local w1, w2 = { name = "w1" }, { name = "w2" }
        local state = { world = w1 }
        local W = stub(state)
        H.equal(W.is_live(w1), true)
        state.world = w2
        H.equal(W.is_live(w1), false, "a handle from a replaced world is not live")
        H.equal(W.is_live(nil), false)
    end)

    H.test("GT A6-F08 live() is nil without managers or without a world manager", function()
        H.equal((stub({ no_managers = true, world = {} })).live(), nil)
        H.equal((stub({ no_world_manager = true, world = {} })).live(), nil)
    end)

    H.test("GT A6-F08 unit_pos() reads Unit.world_position only for a live unit", function()
        local W, positions = stub({ world = {} })
        H.equal(W.unit_pos(nil), nil)
        H.equal(W.unit_pos({ alive = false }), nil)
        H.equal(positions(), 0, "world_position is never called for a dead or missing unit")
        local unit = {}
        local pos = W.unit_pos(unit)
        H.equal(pos.unit, unit)
        H.equal(pos.node, 0)
        H.equal(positions(), 1)
    end)

    H.test("GT A6-F08 the creature spawner never calls Managers.world:world( unguarded", function()
        H.equal(read("_gt_creature_spawner.lua"):find("Managers.world:world(", 1, true), nil)
    end)

    H.test("GT A6-F08 the former guard copies route through mod._gt_world", function()
        for _, name in ipairs({ "_gt_debug_highlights.lua", "_gt_bot_teleport_lab.lua",
                "_gt_solo_qol.lua", "_gt_melee_warning.lua" }) do
            local text = read(name)
            H.equal(text:find('has_world("level_world")', 1, true), nil, name .. " still probes the world itself")
            H.truthy(text:find("mod._gt_world.", 1, true), name .. " does not use the helper")
        end
        -- The in-game check reads these markers; they must survive the refactor.
        H.truthy(read("_gt_debug_highlights.lua"):find("mod._gt459_liveness_gated_dh = true", 1, true))
        H.truthy(read("_gt_bot_teleport_lab.lua"):find("mod._gt459_liveness_gated_lab = true", 1, true))
    end)
end
