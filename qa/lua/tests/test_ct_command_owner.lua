return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local expected = {
        "dump_spawners",
        "dump_potions",
        "dump_boon_loc",
        "ct_boon_price_audit",
        "ct_boon_price_status",
        "dump_boons",
        "dump_buffs",
        "dump_mutators",
        "dump_traits",
        "dump_adventure_names",
        "pool_status",
        "force_inject_pool",
        "cw_status",
    }

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_command_owner.lua")

    H.test("ct command owner preserves the exact registration order", function()
        local cursor = 1
        H.equal(count_plain(owner, "mod:command("), #expected)
        for _, name in ipairs(expected) do
            local needle = 'mod:command("' .. name .. '"'
            local at = assert(owner:find(needle, cursor, true),
                "missing or reordered command " .. name)
            cursor = at + #needle
            H.equal(count_plain(owner, needle), 1, name .. " owner cardinality")
            H.equal(count_plain(entry, needle), 0, name .. " must leave the entry")
        end
    end)

    H.test("ct command owner loads once at the preserved lifecycle boundary", function()
        local needle = "scripts/mods/chaos_wastes_tweaker_dev/_ct_command_owner"
        H.equal(count_plain(entry, needle), 1)
        local lifecycle_at = assert(entry:find("mod.on_disabled = function", 1, true))
        local owner_at = assert(entry:find(needle, 1, true))
        local regression_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression", 1, true))
        H.truthy(lifecycle_at < owner_at,
            "command owner must install after the settings lifecycle")
        H.truthy(owner_at < regression_at,
            "command owner must install before the regression suite")
    end)

    H.test("ct command owner has a bounded five-dependency seam", function()
        local load_at = assert(entry:find(
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_command_owner")({',
            1, true))
        local load_end = assert(entry:find("\n})", load_at, true)) + 2
        local wiring = entry:sub(load_at, load_end)
        for _, field in ipairs({
            "mod = mod",
            "adventure_pool = AdventurePool",
            "dump_pickup_system_state = _dump_pickup_system_state",
            "effective_setting = effective_setting",
            "mod_version = MOD_VERSION",
        }) do
            H.equal(count_plain(wiring, field), 1, field .. " entry wiring")
        end
        for _, field in ipairs({
            "local mod = assert(ctx.mod,",
            "local AdventurePool = assert(ctx.adventure_pool,",
            "local _dump_pickup_system_state = assert(ctx.dump_pickup_system_state,",
            "local effective_setting = assert(ctx.effective_setting,",
            "local MOD_VERSION = assert(ctx.mod_version,",
        }) do
            H.equal(count_plain(owner, field), 1, field .. " owner capture")
        end
        H.equal(count_plain(owner, "mod:hook"), 0)
        H.equal(count_plain(owner, "network_register"), 0)
        H.equal(count_plain(owner, "mod.on_"), 0)
        H.equal(count_plain(owner, "mod.update ="), 0)
    end)

    H.test("ct command installer is inert until an explicit command runs", function()
        local registrations = {}
        local callbacks = {}
        local messages = {}
        local settings = { inject_adventure_maps = false }
        local pool_dumps, pool_injections, pickup_dumps = 0, 0, 0
        local mod = {
            command = function(_, name, _, callback)
                registrations[#registrations + 1] = name
                callbacks[name] = callback
            end,
            echo = function(_, message)
                messages[#messages + 1] = message
            end,
            get = function(_, key)
                return settings[key]
            end,
        }
        local installer = assert(loadfile(root .. "_ct_command_owner.lua"))()
        installer({
            mod = mod,
            adventure_pool = {
                dump_pool_state = function() pool_dumps = pool_dumps + 1 end,
                inject_pool = function()
                    pool_injections = pool_injections + 1
                    return 7
                end,
            },
            dump_pickup_system_state = function(prefix, also_echo)
                pickup_dumps = pickup_dumps + 1
                H.equal(prefix, "[pickup_dump]")
                H.equal(also_echo, true)
            end,
            effective_setting = function() return true end,
            mod_version = "9.8.7-dev",
        })

        H.deep_equal(registrations, expected)
        H.equal(pool_dumps, 0)
        H.equal(pool_injections, 0)
        H.equal(pickup_dumps, 0)

        callbacks.dump_spawners()
        H.equal(pickup_dumps, 1)
        callbacks.pool_status()
        H.equal(pool_dumps, 1)
        callbacks.force_inject_pool()
        H.equal(pool_injections, 0, "disabled injection command must be inert")
        settings.inject_adventure_maps = true
        callbacks.force_inject_pool()
        H.equal(pool_injections, 1)
        callbacks.cw_status()

        local transcript = table.concat(messages, "\n")
        H.truthy(transcript:find("7 adventures injected", 1, true))
        H.truthy(transcript:find("Chaos Wastes Tweaker v9.8.7-dev", 1, true))
    end)
end
