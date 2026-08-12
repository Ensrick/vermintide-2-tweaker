return function(H, repo_root)
    local base = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local module_path = base .. "_cos_la_husk_identity_runtime.lua"
    local entry_path = base .. "cosmetics_tweaker.lua"
    local Runtime = dofile(module_path)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count(source, needle)
        local n, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return n end
            n = n + 1
            at = found + #needle
        end
    end

    local function fixture()
        local hooks, monitor_units, replay_calls = {}, {}, {}
        local owner_player = { peer_id = "peer-a" }
        local managers = {
            player = {
                owner = function(_, unit)
                    if unit == "husk" then return owner_player end
                end,
            },
            world = {
                has_world = function(_, name) return name == "level_world" end,
                world = function(_, name) return "world:" .. name end,
            },
        }
        local store = {
            ["peer-a"] = {
                slot_hat = {
                    kind = "hat", armoury_key = "hat", vanilla_key = "base",
                },
            },
        }
        local mod = {
            _cos_replay = {
                on_edge = function(edge, options)
                    replay_calls[#replay_calls + 1] = {
                        edge = edge, options = options,
                    }
                end,
            },
        }
        function mod:hook_safe(class, method, callback)
            hooks[#hooks + 1] = {
                class = class, method = method, callback = callback,
            }
        end
        function mod:get(key)
            if key == "la_persisted_equips" then return {} end
        end
        function mod:warning() end
        local deps = {
            gk_set = { resolve_variant = function(key)
                if key == "gk" then return { source = "gk" } end
            end },
            custom_hats = { resolve_variant = function(key)
                if key == "hat" then return { source = "hat" } end
            end },
            get_mod = function(name)
                if name == "Loremasters-Armoury" then
                    return { SKIN_LIST = { la = { source = "la" } } }
                end
            end,
            husk_identity = {
                make_spawn_monitor = function(options)
                    return function(unit)
                        monitor_units[#monitor_units + 1] = {
                            unit = unit, options = options,
                        }
                    end
                end,
            },
            la_bridge = {}, la_equips_by_peer = store, la_persist = {},
            score_identity = {}, script_unit = {}, unit = {},
            get_managers = function() return managers end,
            get_profiles = function() return {} end,
            la_replay_policy = {
                wielded_slot = function(_, equipment)
                    return equipment and equipment.wielded_slot
                end,
            },
            dbg = function() end, dbg_alert = function() end,
            printf = function() end,
        }
        local owner = Runtime.install(mod, deps)
        return {
            mod = mod, deps = deps, owner = owner, hooks = hooks,
            store = store, monitor_units = monitor_units,
            replay_calls = replay_calls,
        }
    end

    H.test("Cosmetics LA husk identity owner is exclusive and bounded", function()
        local entry, source = read(entry_path), read(module_path)
        H.equal(count(entry,
            '"scripts/mods/cosmetics_tweaker/_cos_la_husk_identity_runtime").install'), 1)
        H.equal(count(entry,
            'mod:hook_safe("SimpleHuskInventoryExtension", "init"'), 0)
        H.equal(count(source,
            'mod:hook_safe("SimpleHuskInventoryExtension", "init"'), 1)
        for _, forbidden in ipairs({
            "network_register", "network_send", "mod:command(", "mod.update",
            "on_game_state_changed", "on_disabled", "on_unload", "mod:dofile(",
        }) do
            H.equal(source:find(forbidden, 1, true), nil, forbidden)
        end
    end)

    H.test("Cosmetics LA husk identity shares variant and slot policy", function()
        local f = fixture()
        H.equal(f.owner.hook_count, 1)
        H.equal(f.owner.resolve_la_variant("gk").source, "gk")
        H.equal(f.owner.resolve_la_variant("hat").source, "hat")
        H.equal(f.owner.resolve_la_variant("la").source, "la")
        H.equal(f.owner.level_world(), "world:level_world")
        H.equal(f.owner.chars_compatible(
            "units/beings/player/empire_soldier/headpiece/a",
            "units/beings/player/empire_soldier/headpiece/b"), true)
        H.equal(f.owner.chars_compatible(
            "units/beings/player/dwarf_ranger/headpiece/a",
            "units/beings/player/empire_soldier/headpiece/b"), false)
        local item = { template = "template-a", item_type = "type-a" }
        local match, resolved = f.owner.wielded_item_matches(nil, {
            wielded_slot = "slot_melee",
            slots = { slot_melee = { item_data = item } },
        }, "template-a", false)
        H.equal(match, true)
        H.equal(resolved, item)
        H.equal(f.owner.purge_stale_peer_slot(
            f.store, "peer-a", "slot_hat"), true)
        H.equal(f.store["peer-a"], nil)
    end)

    H.test("Cosmetics LA husk identity runs monitor and peer-ready once", function()
        local f = fixture()
        H.equal(#f.hooks, 1)
        f.hooks[1].callback({}, {}, "husk", {})
        H.equal(#f.monitor_units, 1)
        H.equal(f.monitor_units[1].unit, "husk")
        H.equal(#f.replay_calls, 1)
        H.equal(f.replay_calls[1].edge, "peer-ready")
        H.equal(f.replay_calls[1].options.only_peer, "peer-a")
        local again = Runtime.install(f.mod, f.deps)
        H.equal(again, f.owner)
        H.equal(#f.hooks, 1)
    end)
end
