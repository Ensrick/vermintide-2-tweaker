-- Issue #332: execute the client corpse-retention seam with fake engine owners.
-- This locks the authority boundary, exact teardown bookkeeping, fallback
-- forwarding, and the no-RPC invariant without launching the game.
return function(H, repo_root)
    local runtime_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_client_ragdolls.lua"

    local function load_runtime(options)
        options = options or {}
        local hooks = {}
        local registrations = {}
        local prints = {}
        local mod = {
            get = function(_, key)
                H.equal(key, "gt_more_corpses_count")
                return options.cap or 24
            end,
            hook = function(_, class_name, method_name, fn)
                hooks[class_name .. "." .. method_name] = fn
            end,
            _gt_rt_register = function(name, fn)
                registrations[name] = fn
            end,
        }

        local old = {
            get_mod = _G.get_mod,
            Managers = _G.Managers,
            NetworkUnit = _G.NetworkUnit,
            Unit = _G.Unit,
            Actor = _G.Actor,
            ScriptUnit = _G.ScriptUnit,
            printf = _G.printf,
        }

        _G.get_mod = function() return mod end
        local managers = {
            state = {
                network = { game = function() return options.network_live ~= false end },
                game_mode = {
                    is_game_mode_ended = function()
                        return options.game_mode_ended == true
                    end,
                },
            },
        }
        _G.Managers = managers
        _G.NetworkUnit = {
            is_network_unit = function() return options.is_network_unit ~= false end,
            remove_unit = function(unit) unit.network_removed = true end,
        }
        _G.Unit = {
            alive = function() return options.alive ~= false end,
            is_frozen = function() return options.is_frozen == true end,
            disable_animation_state_machine = function(unit)
                unit.animation_disabled = true
            end,
            num_actors = function() return 2 end,
            actor = function(unit, index)
                unit.actors = unit.actors or { {}, {} }
                return unit.actors[index]
            end,
            get_data = function(unit, key)
                if key == "breed" then return unit.breed end
                if key == "unit_name" then return unit.unit_name end
                error("unexpected Unit.get_data key " .. tostring(key))
            end,
            world_position = function(unit) return unit.position or "position" end,
            world_rotation = function(unit) return unit.rotation or "rotation" end,
            copy_scene_graph_local_from = function(clone, source)
                clone.pose_source = source
            end,
        }
        _G.Actor = {
            is_physical = function() return true end,
            set_kinematic = function(actor, value) actor.kinematic = value end,
            set_collision_enabled = function(actor, value) actor.collision = value end,
        }
        _G.ScriptUnit = {
            has_extension = function(unit, name)
                H.equal(name, "health_system")
                return {
                    is_alive = function() return not unit.dead end,
                }
            end,
        }
        _G.printf = function(fmt, ...)
            prints[#prints + 1] = string.format(fmt, ...)
        end

        local ok, err = pcall(assert(loadfile(runtime_path)))
        _G.get_mod = old.get_mod
        _G.Managers = old.Managers
        _G.NetworkUnit = old.NetworkUnit
        _G.Unit = old.Unit
        _G.Actor = old.Actor
        _G.ScriptUnit = old.ScriptUnit
        _G.printf = old.printf
        if not ok then error(err, 0) end

        return mod, hooks, registrations, prints, managers
    end

    local function fake_spawner(options)
        options = options or {}
        local units = {}
        local storage = {
            unit = function(_, go_id)
                return units[go_id]
            end,
            go_id = function(_, candidate)
                return candidate.go_id
            end,
            remove = function(_, candidate, go_id)
                H.equal(candidate, units[go_id])
                candidate.storage_removed = true
                units[go_id] = nil
                candidate.go_id = nil
            end,
        }
        local self = {
            is_server = options.is_server == true,
            unit_storage = storage,
            marked = {},
            spawned = {},
            entity_manager = {
                game_object_unit_destroyed = function(_, candidate)
                    candidate.extensions_notified = true
                end,
            },
        }
        function self:mark_for_deletion(unit)
            unit.marked = true
            self.marked[#self.marked + 1] = unit
        end
        function self:spawn_local_unit(unit_name, position, rotation)
            local clone = {
                unit_name = unit_name,
                position = position,
                rotation = rotation,
            }
            self.spawned[#self.spawned + 1] = clone
            return clone
        end
        local function add(go_id, unit_options)
            unit_options = unit_options or {}
            local unit = {
                go_id = go_id,
                dead = unit_options.dead ~= false,
                breed = { is_player = unit_options.is_player == true },
                unit_name = unit_options.unit_name or "units/test/dead_ai",
            }
            units[go_id] = unit
            return unit
        end
        return self, add
    end

    H.test("GT #332 snapshots a host-pruned husk and preserves vanilla teardown", function()
        local _, hooks, registrations, prints = load_runtime({ cap = 24 })
        local hook = hooks["UnitSpawner.destroy_game_object_unit"]
        H.truthy(hook)
        local self, add = fake_spawner()
        local unit = add(17)
        local vanilla_calls = 0
        hook(function() vanilla_calls = vanilla_calls + 1 end, self, 17, "host")
        H.equal(vanilla_calls, 1)
        H.equal(#self.spawned, 1)
        local clone = self.spawned[1]
        H.equal(clone.pose_source, unit)
        H.equal(clone.animation_disabled, true)
        H.equal(clone.actors[1].kinematic, true)
        H.equal(clone.actors[1].collision, false)
        H.equal(clone.actors[2].kinematic, true)
        H.equal(clone.actors[2].collision, false)
        H.equal(unit.marked, nil)
        H.equal(#prints, 1)
        H.truthy(prints[1]:find("[gt:332] retained client-local corpse", 1, true))
        -- Runner contract (#1153 / PROJECT_STANDARDS 5.1d rule 3): nil == PASS.
        H.equal(registrations.issue332_client_ragdoll_retention(), nil)
    end)

    H.test("GT #332 preserves vanilla teardown outside its exact client corpse scope", function()
        local cases = {
            { runtime = {}, spawner = { is_server = true } },
            { runtime = { is_frozen = true }, spawner = {} },
            { runtime = { network_live = false }, spawner = {} },
            { runtime = { game_mode_ended = true }, spawner = {} },
            { runtime = {}, unit = { dead = false } },
            { runtime = {}, unit = { is_player = true } },
        }
        for _, case in ipairs(cases) do
            local _, hooks = load_runtime(case.runtime)
            local self, add = fake_spawner(case.spawner)
            add(17, case.unit)
            local vanilla_calls = 0
            hooks["UnitSpawner.destroy_game_object_unit"](
                function(forwarded_self, go_id, owner_id)
                    H.equal(forwarded_self, self)
                    H.equal(go_id, 17)
                    H.equal(owner_id, "host")
                    vanilla_calls = vanilla_calls + 1
                end, self, 17, "host")
            H.equal(vanilla_calls, 1)
            H.equal(#self.spawned, 0)
        end
    end)

    H.test("GT #332 client corpse FIFO keeps the newest units within the local cap", function()
        local mod, hooks, _, _, managers = load_runtime({ cap = 2 })
        local self, add = fake_spawner()
        local a, b, c = add(1), add(2), add(3)
        local hook = hooks["UnitSpawner.destroy_game_object_unit"]
        hook(function() end, self, 1, "host")
        hook(function() end, self, 2, "host")
        hook(function() end, self, 3, "host")
        H.equal(a.marked, nil)
        H.equal(b.marked, nil)
        H.equal(c.marked, nil)
        H.equal(self.spawned[1].marked, true)
        H.equal(self.spawned[2].marked, nil)
        H.equal(self.spawned[3].marked, nil)
        H.equal(#self.marked, 1)

        mod.get = function() return 1 end
        managers.state.unit_spawner = self
        H.equal(mod._gt332_reconcile_client_corpses(), 1)
        H.equal(self.spawned[2].marked, true)
        H.equal(self.spawned[3].marked, nil)
        H.equal(#self.marked, 2)
    end)

    H.test("GT #332 snapshots pooled trash before the client freezer consumes it", function()
        local _, hooks, _, _, managers = load_runtime({ cap = 4 })
        local self, add = fake_spawner()
        local unit = add(41)
        managers.state.unit_spawner = self
        managers.state.unit_storage = self.unit_storage
        local vanilla_calls = 0
        hooks["BreedFreezer.rpc_breed_freeze_units"](
            function(forwarded_self, channel_id, ids)
                H.equal(forwarded_self.is_server, false)
                H.equal(channel_id, 9)
                H.equal(ids[1], 41)
                vanilla_calls = vanilla_calls + 1
            end,
            { is_server = false }, 9, { 41 })
        H.equal(vanilla_calls, 1)
        H.equal(#self.spawned, 1)
        H.equal(self.spawned[1].pose_source, unit)
    end)

    H.test("GT #332 client corpse retention adds no mod RPC surface", function()
        local f = assert(io.open(runtime_path, "rb"))
        local source = f:read("*a")
        f:close()
        H.equal(source:find("network_send", 1, true), nil)
        H.equal(source:find("network_register", 1, true), nil)
        local _, destroy_hook_count = source:gsub(
            'mod:hook%("UnitSpawner", "destroy_game_object_unit"', "")
        local _, freeze_hook_count = source:gsub(
            'mod:hook%("BreedFreezer", "rpc_breed_freeze_units"', "")
        H.equal(destroy_hook_count, 1)
        H.equal(freeze_hook_count, 1)
        H.truthy(source:find("return func(self, go_id, owner_id)", 1, true))
        H.truthy(source:find("return func(self, channel_id, unit_go_ids)", 1, true))
    end)
end
