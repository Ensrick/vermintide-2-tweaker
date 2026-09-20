-- Behavioral coverage for the #1637 consumer-boundary recovery adapter.
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_gut_native_loadout_policy.lua"))()
    local Recovery = assert(loadfile(root .. "_gut_spawn_weapon_recovery.lua"))()

    local function with_globals(managers, printf_fn, fn)
        local old_managers, old_printf = rawget(_G, "Managers"), rawget(_G, "printf")
        rawset(_G, "Managers", managers)
        rawset(_G, "printf", printf_fn)
        local result = { pcall(fn) }
        rawset(_G, "Managers", old_managers)
        rawset(_G, "printf", old_printf)
        if not result[1] then error(result[2], 0) end
    end

    H.test("GUT #1637 adapter recovers a live official weapon without mutating loadouts", function()
        local selected = { slot_melee = "official_melee" }
        local defaults = { { slot_melee = "default_melee" } }
        local mirror = {
            _career_loadouts = { bw_unchained = 2 },
            _career_data = { bw_unchained = { [2] = selected } },
        }
        function mirror:get_default_loadouts(career)
            H.equal(career, "bw_unchained")
            return defaults
        end
        local iface = { _backend_mirror = mirror }
        function iface:get_item_from_id(id)
            if id == "official_melee" then return { backend_id = id } end
        end
        local logs = 0
        with_globals({ backend = { _interfaces = { items = iface } } }, function()
            logs = logs + 1
        end, function()
            local recover = Recovery.new(Policy, function(seen)
                H.equal(seen, iface)
                return Policy.MODE_STORE
            end, Policy.MODE_STORE)
            local item = recover("bw_unchained", "slot_melee", false)
            H.equal(item.backend_id, "official_melee")
            recover("bw_unchained", "slot_melee", false)
        end)
        H.equal(selected.slot_melee, "official_melee")
        H.equal(defaults[1].slot_melee, "default_melee")
        H.equal(logs, 1)
    end)

    H.test("GUT #1637 adapter is inert outside STORE mode and without an item interface", function()
        local resolve_calls = 0
        local iface = {
            _backend_mirror = {
                _career_loadouts = { bw_unchained = 1 },
                _career_data = { bw_unchained = { { slot_melee = "weapon" } } },
                get_default_loadouts = function() return {} end,
            },
            get_item_from_id = function()
                resolve_calls = resolve_calls + 1
                return { backend_id = "weapon" }
            end,
        }
        with_globals({ backend = { _interfaces = { items = iface } } }, nil, function()
            local recover = Recovery.new(Policy, function() return Policy.MODE_READONLY end,
                Policy.MODE_STORE)
            H.equal(recover("bw_unchained", "slot_melee", false), nil)
        end)
        with_globals({ backend = { _interfaces = {} } }, nil, function()
            local recover = Recovery.new(Policy, function() return Policy.MODE_STORE end,
                Policy.MODE_STORE)
            H.equal(recover("bw_unchained", "slot_melee", false), nil)
        end)
        H.equal(resolve_calls, 0)
    end)
end
