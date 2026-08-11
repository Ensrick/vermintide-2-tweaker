return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local function table_count(value)
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        return count
    end

    local entry = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local host_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_picker_host.lua"
    local wield_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_local_wield_runtime.lua"
    local host_source = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_picker_host.lua")
    local wield_source = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_local_wield_runtime.lua")

    H.test("cos bottom runtime owners retain exact entry positions and boundaries", function()
        local host_install =
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_picker_host").install'
        local wield_install =
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_local_wield_runtime").install'
        H.equal(occurrences(entry, host_install), 1)
        H.equal(occurrences(entry, wield_install), 1)
        H.truthy(entry:find("_cos_husk_cache_bridge", 1, true)
            < entry:find(host_install, 1, true))
        H.truthy(entry:find(host_install, 1, true)
            < entry:find(wield_install, 1, true))
        H.truthy(entry:find(wield_install, 1, true)
            < entry:find("local _cos_runtime_checks", 1, true))
        H.equal(occurrences(entry,
            'mod:hook_safe("HeroWindowCosmeticsLoadout"'), 0)
        H.equal(occurrences(entry,
            'mod:hook_safe("HeroWindowItemCustomization", "_draw"'), 0)
        H.equal(occurrences(entry,
            'mod:hook_safe("SimpleInventoryExtension", "_wield_slot"'), 0)
    end)

    H.test("cos bottom runtime owners are bounded and network-free", function()
        H.equal(occurrences(host_source,
            'mod:hook_safe("HeroWindowCosmeticsLoadout"'), 3)
        H.equal(occurrences(host_source,
            'mod:hook_safe("HeroWindowItemCustomization"'), 2)
        H.equal(occurrences(host_source, 'mod:command("glow_picker"'), 1)
        H.equal(occurrences(host_source,
            'mod:command("glow_picker_hooks"'), 1)
        H.equal(occurrences(wield_source,
            'mod:hook_safe("SimpleInventoryExtension", "_wield_slot"'), 1)
        for _, source in ipairs({ host_source, wield_source }) do
            H.equal(source:find("network_register", 1, true), nil)
            H.equal(source:find("network_send", 1, true), nil)
            H.truthy(source:find("Owned by:", 1, true))
            H.truthy(source:find("Consumed via:", 1, true))
        end
    end)

    H.test("cos glow picker host installs once and refreshes action dependencies", function()
        local hooks, commands, info = {}, {}, {}
        local mod = { _unit_to_backend_id = {} }
        function mod:hook_safe(class_name, method_name, fn)
            hooks[class_name .. ":" .. method_name] = fn
        end
        function mod:command(name, _description, fn) commands[name] = fn end
        function mod:info(format, ...)
            info[#info + 1] = string.format(format, ...)
        end
        function mod:echo() end

        local calls_a, calls_b = {}, {}
        local function picker(calls)
            local open = true
            return {
                _built = true,
                is_open = function() return open end,
                close = function() open = false; calls[#calls + 1] = "close" end,
                handle_input = function(_, host)
                    calls[#calls + 1] = host and "input-custom" or "input-loadout"
                end,
                draw = function(renderer, _input, _dt, host)
                    calls[#calls + 1] = (host and "draw-custom:" or "draw-loadout:")
                        .. tostring(renderer)
                end,
                open_for = function(backend_id)
                    open = true
                    calls[#calls + 1] = "open:" .. tostring(backend_id)
                end,
            }
        end
        local deps_a = {
            glow_picker = picker(calls_a), printf = function() end,
            mod_version = "a", wielded_units_for_probe = function() return {} end,
        }
        local owner_a = assert(loadfile(host_path))().install(mod, deps_a)
        H.equal(owner_a.hook_count, 5)
        H.equal(owner_a.command_count, 2)
        H.equal(table_count(hooks), 5)
        H.equal(table_count(commands), 2)

        local unit = {}
        mod._unit_to_backend_id[unit] = "bid-b"
        local deps_b = {
            glow_picker = picker(calls_b), printf = function() end,
            mod_version = "b",
            wielded_units_for_probe = function()
                return { { unit = unit } }, { id = "slot" }
            end,
        }
        local owner_b = assert(loadfile(host_path))().install(mod, deps_b)
        H.equal(owner_b, owner_a)
        H.equal(table_count(hooks), 5)
        H.equal(table_count(commands), 2)

        local loadout = {
            ui_top_renderer = "loadout-renderer",
            parent = { window_input_service = function() return "input" end },
        }
        hooks["HeroWindowCosmeticsLoadout:update"](loadout, 0.1, 1)
        hooks["HeroWindowCosmeticsLoadout:draw"](loadout, 0.1)
        hooks["HeroWindowCosmeticsLoadout:on_exit"](loadout, {})
        commands.glow_picker()
        H.equal(#calls_a, 0)
        H.equal(table.concat(calls_b, ","),
            "input-loadout,draw-loadout:loadout-renderer,close,open:bid-b")
        H.equal(#info, 3)
    end)

    H.test("cos local wield owner replays exact local LA and glow state once", function()
        local hook_count, callback = 0, nil
        local local_unit, glow_unit = {}, {}
        local reconciles, binds, applied, emitted, probes = {}, {}, {}, 0, {}
        local mod = {
            _unit_to_backend_id = { [glow_unit] = "bid" },
            _per_item_glow_runtime = { bid = { r = 1 } },
            _per_item_glow_identity_runtime = { bid = "identity" },
            _cos = {},
        }
        function mod:hook_safe(class_name, method_name, fn)
            H.equal(class_name, "SimpleInventoryExtension")
            H.equal(method_name, "_wield_slot")
            hook_count, callback = hook_count + 1, fn
        end
        mod._cos518_owner_wield = function() end
        mod._la_deus_weapon_yield = function() return false end
        mod._la_reconcile = function(peer, template, reason, pulse)
            reconciles[#reconciles + 1] = { peer, template, reason, pulse }
        end
        mod._emit_per_item_glow = function() emitted = emitted + 1 end
        mod._cos.bind_glow_unit = function(unit, backend_id)
            binds[#binds + 1] = { unit, backend_id }
        end
        mod._cos.apply_glow_override = function(units, peer)
            applied[#applied + 1] = { units, peer }
        end

        local managers = { player = {} }
        local deps = {
            local_player_safe = function()
                return { player_unit = local_unit, peer_id = "peer" }
            end,
            get_managers = function() return managers end,
            unit = { alive = function(unit) return unit == local_unit end },
            la_equips_by_peer = {
                peer = { template = { armoury_key = "shield", kind = "offhand" } },
            },
            glow_picker = {
                restore_runtime_for = function(backend_id)
                    H.equal(backend_id, "bid")
                end,
            },
            trace = function() end,
            glow_log = function() end,
            probe = { emit = function(...) probes[#probes + 1] = { ... } end },
        }
        local owner = assert(loadfile(wield_path))().install(mod, deps)
        H.equal(owner.hook_count, 1)
        H.equal(hook_count, 1)
        assert(loadfile(wield_path))().install(mod, deps)
        H.equal(hook_count, 1)

        callback({ _unit = local_unit, _equipment = {} }, {}, {
            id = "slot_melee", skin = "skin",
            item_data = { name = "item", template = "template" },
            right_unit_3p = glow_unit,
        })
        H.equal(#reconciles, 1)
        H.equal(reconciles[1][1], "peer")
        H.equal(reconciles[1][2], "template")
        H.equal(reconciles[1][3], "local-wield")
        H.equal(reconciles[1][4], false)
        H.equal(#probes, 1)
        H.equal(#binds, 1)
        H.equal(binds[1][2], "bid")
        H.equal(#applied, 1)
        H.equal(applied[1][2], "peer")
        H.equal(emitted, 1)
        H.equal(mod._active_per_item_glow_identity, "identity")

        callback({ _unit = {} }, {}, { id = "slot_ranged" })
        H.equal(#applied, 1)
    end)
end
