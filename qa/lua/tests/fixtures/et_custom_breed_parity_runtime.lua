return function(H, repo_root)
    local Identity = assert(loadfile(repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_identity.lua"))()

    local function pair(lookup, id, name)
        lookup[id], lookup[name] = name, id
    end

    local function fixture(offset)
        offset = offset or 0
        local marker_key = "_et_custom_breed_registration"
        local breeds = {
            chaos_warrior = { name = "chaos_warrior" },
            skaven_storm_vermin_champion = { name = "skaven_storm_vermin_champion" },
        }
        local network_lookup = {
            breeds = {}, damage_sources = {}, statistics_path_names = {},
        }
        pair(network_lookup.breeds, 1 + offset, "chaos_warrior")
        pair(network_lookup.breeds, 2 + offset, "skaven_storm_vermin_champion")
        local ids = {
            et_chosen_greataxe = { 11 + offset, 31 + offset, 51 + offset },
            et_skaven_warlord = { 12 + offset, 32 + offset, 52 + offset },
        }
        for _, spec in ipairs(Identity.SPECS) do
            local row = ids[spec.name]
            local marker = {
                schema = 3,
                owner = spec.owner,
                fingerprint = spec.fingerprint,
                breed_index = row[1],
                damage_source_index = row[2],
                statistics_path_index = row[3],
            }
            breeds[spec.name] = { name = spec.name, [marker_key] = marker }
            pair(network_lookup.breeds, row[1], spec.name)
            pair(network_lookup.damage_sources, row[2], spec.name)
            pair(network_lookup.statistics_path_names, row[3], spec.name)
        end
        return {
            breeds = breeds,
            network_lookup = network_lookup,
            marker_key = marker_key,
            registrar_schema = 3,
        }
    end
    local function install_runtime(options)
        options = options or {}
        local hooks, safe_hooks, logs, sends, checks = {}, {}, {}, {}, {}
        local check_options = {}
        local latest, receiver = {}, nil
        local ctx = fixture()
        if options.identity_capture_failure then
            ctx.breeds.et_chosen_greataxe[ctx.marker_key].fingerprint =
                "fixture-breed-mismatch"
        end
        local supplied_live = options.live_counts or {}
        local supplied_queued = options.queued_counts or {}
        local live_counts, queued_counts = {}, {}
        for i = 1, #Identity.SPECS do
            local name = Identity.SPECS[i].name
            live_counts[name] = supplied_live[name] or 0
            queued_counts[name] = supplied_queued[name] or 0
        end
        local roster = options.roster or {}
        local registrar = {
            marker_key = ctx.marker_key,
            schema = ctx.registrar_schema,
            validate_all_registered = function() return true end,
        }
        local mod = {
            _et = {
                CustomBreedIdentity = Identity,
                CustomBreedRegistrar = registrar,
                rpc_schema = 1,
                rt_register = function(name, fn, opts)
                    checks[name] = fn
                    check_options[name] = opts
                end,
            },
            dofile = function(_, path)
                H.equal(path,
                    "scripts/mods/enemy_tweaker/_lib_peer_parity")
                if options.parity_unavailable then error("parity unavailable") end
                return assert(loadfile(repo_root
                    .. "/tools/shared_lib/_lib_peer_parity.lua"))()
            end,
            hook = function(_, class, method, callback)
                hooks[class .. "." .. method] = callback
            end,
            hook_safe = function(_, class, method, callback)
                safe_hooks[class .. "." .. method] = callback
            end,
            network_register = function(_, channel, callback)
                H.equal(channel, "et_custom_breeds_exact_v1")
                receiver = callback
            end,
            network_send = function(_, channel, recipient, schema, reply,
                    identity, epoch, query, echo)
                local row = {
                    channel = channel, recipient = recipient, schema = schema,
                    reply = reply, identity = identity, epoch = epoch,
                    query = query, echo = echo,
                }
                sends[#sends + 1] = row
                latest[recipient] = row
            end,
            debug = function() end,
            echo = function() end,
            get_name = function() return "enemy_tweaker" end,
        }
        local runtime = {
            ctx = ctx,
            mod = mod,
            hooks = hooks,
            safe_hooks = safe_hooks,
            checks = checks,
            check_options = check_options,
            logs = logs,
            sends = sends,
            latest = latest,
            live_counts = live_counts,
            queued_counts = queued_counts,
            roster = roster,
            network = {
                own_peer_id = options.own_peer_id or "host",
                peer_id_throws = options.peer_id_throws == true,
            },
            managers = {
                player = {
                    human_players = function() return roster end,
                },
                state = {
                    conflict = {
                        num_queued_spawn_by_breed = queued_counts,
                        count_units_by_breed = function(_, name)
                            return live_counts[name]
                        end,
                    },
                },
            },
        }
        runtime.receiver = function(...)
            H.equal(type(receiver), "function", "parity receiver not installed")
            return receiver(...)
        end
        runtime.reply_exact = function(peer_id, epoch)
            local challenge = assert(latest[peer_id],
                "directed challenge missing for " .. tostring(peer_id))
            receiver(peer_id, 1, 1,
                assert(mod._et.CustomBreedIdentitySnapshot).identity,
                epoch or ("epoch-" .. peer_id), "", challenge.query)
        end
        runtime.reply_mismatch = function(peer_id, epoch)
            local challenge = assert(latest[peer_id],
                "directed challenge missing for " .. tostring(peer_id))
            receiver(peer_id, 1, 1, "wrong-identity",
                epoch or ("epoch-" .. peer_id), "", challenge.query)
        end
        return runtime
    end

    local function with_runtime(options, callback)
        local previous = {
            get_mod = rawget(_G, "get_mod"),
            Breeds = rawget(_G, "Breeds"),
            NetworkLookup = rawget(_G, "NetworkLookup"),
            Managers = rawget(_G, "Managers"),
            Network = rawget(_G, "Network"),
            printf = rawget(_G, "printf"),
        }
        local runtime = install_runtime(options)
        local ok, err = xpcall(function()
            get_mod = function() return runtime.mod end
            Breeds = runtime.ctx.breeds
            NetworkLookup = runtime.ctx.network_lookup
            Managers = runtime.managers
            Network = { peer_id = function()
                if runtime.network.peer_id_throws then
                    error("network-peer-id-threw")
                end
                return runtime.network.own_peer_id
            end }
            printf = function(fmt, ...)
                runtime.logs[#runtime.logs + 1] = string.format(fmt, ...)
            end
            assert(loadfile(repo_root
                .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_parity.lua"))()
            callback(runtime)
        end, debug.traceback)
        get_mod = previous.get_mod
        Breeds = previous.Breeds
        NetworkLookup = previous.NetworkLookup
        Managers = previous.Managers
        Network = previous.Network
        printf = previous.printf
        if not ok then error(err, 0) end
    end
    return {
        Identity = Identity,
        fixture = fixture,
        install_runtime = install_runtime,
        with_runtime = with_runtime,
    }
end
