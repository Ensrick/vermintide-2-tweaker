-- Guards the #1159 peer-manifest owner extraction. The fixture executes the
-- real owner without engine dependencies and pins its wire and ownership seams.
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_peer_manifest_owner.lua"

    local function read(name)
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

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_peer_manifest_owner.lua")

    local function with_engine_globals(body)
        local names = { "Managers", "NetworkLookup", "Application", "printf", "bit" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
        Managers = {
            player = { is_server = false },
            mod = { _mods = {
                { enabled = true, id = "1369573612", name = "VMF", last_updated = 77 },
                { enabled = true, id = "ct", name = "Chaos Wastes Tweaker", timestamp = 88 },
                { enabled = false, id = "off", name = "Disabled" },
            } },
        }
        NetworkLookup = { level_keys = { "a", "b", "c" } }
        Application = { time_since_launch = function() return 1.25 end }
        printf = function() end
        bit = nil -- exercise the owner's deterministic fallback hash path
        local ok, err = pcall(body)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end

    local function fixture(overrides)
        overrides = overrides or {}
        local rpcs, commands, enqueued, logs, echoes = {}, {}, {}, {}, {}
        local settings = { alpha = true, beta = 4 }
        local decode_count = 0
        local mod = {}
        function mod:get(name) return settings[name] end
        function mod:network_register(name, callback)
            H.equal(rpcs[name], nil, "duplicate rpc " .. name)
            rpcs[name] = callback
        end
        function mod:command(name, _, callback)
            H.equal(commands[name], nil, "duplicate command " .. name)
            commands[name] = callback
        end
        function mod:echo(message) echoes[#echoes + 1] = message end

        local ctx = {
            chunk_size = 4,
            cjson = {
                encode = function() return "ABCDEFGHI" end,
                decode = function(json)
                    decode_count = decode_count + 1
                    if json == "LEFT-RIGHT" then
                        return { v = "peer", h = 9, m = {}, nl = 3 }
                    end
                    error("unexpected json " .. tostring(json))
                end,
            },
            dbg = function(fmt, ...)
                logs[#logs + 1] = string.format(fmt, ...)
            end,
            dbg_alert = function(fmt, ...)
                logs[#logs + 1] = string.format(fmt, ...)
            end,
            enqueue_chunk = function(...)
                enqueued[#enqueued + 1] = { ... }
            end,
            mod_version = "0.7.fixture-dev",
            rpc_schema = 11,
            synced_setting_names = { "alpha", "beta" },
        }
        for key, value in pairs(overrides) do
            if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
        end
        local installer = assert(loadfile(module_path))()
        local exports = installer(mod, ctx)
        return {
            commands = commands,
            decode_count = function() return decode_count end,
            echoes = echoes,
            enqueued = enqueued,
            exports = exports,
            logs = logs,
            rpcs = rpcs,
        }
    end

    H.test("peer-manifest owner is a named ctx installer", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is installed once at the former inline boundary", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_manifest_owner"), 1)
        local graph = assert(entry:find(
            '_ct_enqueue_chunk("ct_graph_snapshot_chunk"', 1, true))
        local install_at = assert(entry:find("_ct_peer_manifest_owner", graph, true))
        local effective = assert(entry:find("effective_setting = function(name)", install_at, true))
        H.truthy(graph < install_at and install_at < effective,
            "manifest owner must remain between graph broadcast and effective-setting assignment")
        H.truthy(entry:find(
            "_broadcast_local_manifest = _ct_peer_manifest.broadcast_local_manifest", 1, true))
    end)

    H.test("RPC and command have exactly one owner", function()
        for _, needle in ipairs({
            '\n    mod:network_register("ct_peer_manifest_chunk"',
            '\n    mod:command("peers"',
        }) do
            H.equal(count_plain(owner, needle), 1, needle .. " owned once")
            H.equal(count_plain(entry, needle), 0, needle .. " absent from entry")
        end
    end)

    H.test("dropped ctx dependencies fail at install", function()
        with_engine_globals(function()
            for _, key in ipairs({
                "chunk_size", "cjson", "dbg", "dbg_alert", "enqueue_chunk",
                "mod_version", "rpc_schema", "synced_setting_names",
            }) do
                local ok = pcall(function() fixture({ [key] = "\0drop" }) end)
                H.equal(ok, false, "missing " .. key .. " must fail")
            end
        end)
    end)

    H.test("local manifest uses ordered local settings and enabled local mods", function()
        with_engine_globals(function()
            local f = fixture()
            local first = f.exports.build_local_manifest()
            local second = f.exports.build_local_manifest()
            H.equal(first.v, "0.7.fixture-dev")
            H.equal(first.h, second.h, "same ordered settings must hash identically")
            H.equal(first.nl, 3)
            H.equal(first.vt, 77)
            H.equal(#first.m, 2)
            H.equal(first.m[1].i, "1369573612")
            H.equal(first.m[2].n, "Chaos Wastes Tweaker")
        end)
    end)

    H.test("broadcast chunks only through the shared paced enqueue seam", function()
        with_engine_globals(function()
            local f = fixture()
            local _, bytes, total = f.exports.broadcast_local_manifest("server")
            H.equal(bytes, 9)
            H.equal(total, 3)
            H.equal(#f.enqueued, 3)
            H.equal(f.enqueued[1][1], "ct_peer_manifest_chunk")
            H.equal(f.enqueued[1][2], "server")
            H.equal(f.enqueued[1][3], 11)
            H.equal(f.enqueued[1][5], 1)
            H.equal(f.enqueued[1][6], 3)
            H.equal(f.enqueued[1][7], "ABCD")
            H.equal(f.enqueued[3][7], "I")
        end)
    end)

    H.test("schema mismatch rejects before decode or state mutation", function()
        with_engine_globals(function()
            local f = fixture()
            f.rpcs.ct_peer_manifest_chunk("peer-a", 10, 1, 1, 1, "LEFT-RIGHT")
            H.equal(f.decode_count(), 0)
            H.truthy(table.concat(f.logs, "\n"):find("mismatch", 1, true))
        end)
    end)

    H.test("receiver reassembles out of order and ignores duplicate chunks", function()
        with_engine_globals(function()
            local f = fixture()
            local recv = f.rpcs.ct_peer_manifest_chunk
            recv("peer-a", 11, 7, 2, 2, "RIGHT")
            recv("peer-a", 11, 7, 2, 2, "RIGHT")
            H.equal(f.decode_count(), 0)
            recv("peer-a", 11, 7, 1, 2, "LEFT-")
            H.equal(f.decode_count(), 1)
            H.truthy(table.concat(f.logs, "\n"):find("RECV peer=peer-a", 1, true))
        end)
    end)

    H.test("peers command refreshes over the same broadcast path", function()
        with_engine_globals(function()
            local f = fixture()
            H.equal(type(f.commands.peers), "function")
            f.commands.peers()
            H.equal(#f.enqueued, 3)
            H.equal(f.enqueued[1][2], "all")
            H.equal(#f.echoes, 1)
            H.truthy(f.echoes[1]:find("dumped 0 cached", 1, true))
        end)
    end)
end
