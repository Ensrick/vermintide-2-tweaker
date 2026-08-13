return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)
    local dispatch = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
        .. "_cwv_remote_audio_dispatch.lua")
    local install_wire = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_wire.lua")

    H.test("CWV cross-access remap owns the pre-RPC 3P animation seam", function()
        H.truthy(source:find('mod:hook("WeaponUnitExtension", "_play_3p_anim"', 1, true))
        H.truthy(source:find("_cwv_networked_3p_remap_installed = true", 1, true))
        H.equal(source:find('mod:hook("Unit", "animation_event"', 1, true), nil)
    end)

    H.test("CWV delegates substituted animation and audio to vanilla", function()
        local hook_start = assert(source:find(
            'mod:hook("WeaponUnitExtension", "_play_3p_anim"', 1, true
        ))
        local hook_end = assert(source:find(
            "_cwv_networked_3p_remap_installed = true", hook_start, true
        ))
        local hook = source:sub(hook_start, hook_end)
        H.truthy(hook:find("_om.remote_audio_dispatch.invoke(func, self, event_3p, event,", 1, true))
        H.equal(hook:find("WwiseWorld.trigger_event", 1, true), nil)
        H.equal(hook:find("rpc_play_sound_event", 1, true), nil)
    end)

    H.test("CWV #398 executable dispatch substitutes only the local receiver event", function()
        local owner, remote = {}, {}
        local calls = {}
        local function spy(self, event_3p, event, got_owner, looping, scale)
            calls[#calls + 1] = {
                self = self, event_3p = event_3p, event = event,
                owner = got_owner, looping = looping, scale = scale,
            }
            return "vanilla", event_3p
        end
        local before = 0
        local applied, declined = 0, 0
        local function resolve(source_event)
            if source_event == "donor_heavy" then return "receiver_heavy" end
        end
        local function lookup(target)
            return target == "receiver_heavy" and 77 or nil
        end

        local status, event = dispatch.invoke(spy, "self", "donor_heavy",
            "attack_one", owner, true, 1.25, owner,
            function() before = before + 1 end, resolve, lookup,
            function(source, target, id)
                H.equal(source, "donor_heavy")
                H.equal(target, "receiver_heavy")
                H.equal(id, 77)
                applied = applied + 1
            end,
            function() declined = declined + 1 end)
        H.equal(status, "vanilla")
        H.equal(event, "receiver_heavy")
        H.equal(#calls, 1)
        H.equal(calls[1].event_3p, "receiver_heavy")
        H.equal(calls[1].event, "attack_one")
        H.equal(calls[1].owner, owner)
        H.equal(calls[1].looping, true)
        H.equal(calls[1].scale, 1.25)
        H.equal(before, 1)
        H.equal(applied, 1)
        H.equal(declined, 0)

        dispatch.invoke(spy, "self", "donor_heavy", "attack_one",
            remote, false, 1, owner, function() before = before + 1 end,
            resolve, lookup)
        H.equal(#calls, 2)
        H.equal(calls[2].event_3p, "donor_heavy")
        H.equal(before, 1, "non-owner calls must not enter the remap decision")

        dispatch.invoke(spy, "self", "donor_heavy", "attack_one",
            owner, false, 1, owner, nil, resolve, function() return nil end,
            nil, function() declined = declined + 1 end)
        H.equal(#calls, 3)
        H.equal(calls[3].event_3p, "donor_heavy")
        H.equal(declined, 1)

        dispatch.invoke(spy, "self", "donor_heavy", "attack_one",
            owner, false, 1, nil, nil, resolve, lookup)
        H.equal(#calls, 4)
        H.equal(calls[4].event_3p, "donor_heavy")
    end)

    -- #1211: the remote Old Musket shot fed Application.main_world() into
    -- WwiseUtils. WorldManager Wwise-registers a world ONLY in create_world, so
    -- that handle is never a key and wwise_utils.lua:40 called
    -- WwiseWorld.make_auto_source(nil, ...) -- a native access violation that the
    -- surrounding pcall cannot catch. Both delivery wires (the bounded mode
    -- channel and the cwv_item_identity musket-fire sentinel) route through the
    -- single play_remote_fire choke point, so the guard is asserted there.
    local function play_remote_fire_slice()
        local start = assert(source:find("local function play_remote_fire(", 1, true))
        local finish = assert(source:find(
            "_om._old_musket_play_remote_fire = play_remote_fire", start, true))
        return source:sub(start, finish)
    end

    H.test("CWV remote musket fire never resolves a world outside WorldManager", function()
        H.equal(source:find("Application.main_world", 1, true), nil,
            "an Application-owned world is never a WorldManager wwise key (#1211)")
        H.equal(source:find("Application.new_world", 1, true), nil)
        H.truthy(source:find('local LEVEL_WORLD = "level_world"', 1, true))
        H.truthy(source:find("if not wm:has_world(LEVEL_WORLD) then return nil, nil end", 1, true))
        H.truthy(source:find("return wm:wwise_world(world), world", 1, true))

        local fire = play_remote_fire_slice()
        H.equal(fire:find("main_world", 1, true), nil)
        H.truthy(fire:find("local wwise_world, world = registered_level_world()", 1, true))
        H.truthy(fire:find("if not wwise_world then", 1, true))
        H.truthy(fire:find("[cwv:1211] remote fire audio skipped: ", 1, true))
        H.truthy(fire:find("no registered wwise world (world=%s)", 1, true))

        -- Both entry wires must keep calling the shared acceptor rather than
        -- reimplementing the audio call with their own world handle.
        H.truthy(source:find('if valid_bid(bid) then play_remote_fire(sender_peer_id, mode, "mode_channel") end',
            1, true))
        H.truthy(source:find("_om._old_musket_play_remote_fire(sender_peer_id, payload.fire_event", 1, true))
    end)

    -- Behavioral half: install the real wire module against stub engine globals
    -- and prove the native Wwise entry point is reached ONLY when the resolved
    -- level world has a registered wwise world.
    local function with_stub_engine(registered, body)
        local saved = {
            Managers = _G.Managers,
            Unit = _G.Unit,
            WwiseUtils = _G.WwiseUtils,
            printf = _G.printf,
        }
        local level_world = { "level_world_handle" }
        local wwise_world = { "wwise_world_handle" }
        local native, logged = {}, {}
        _G.Unit = { alive = function() return true end }
        _G.printf = function(format, ...)
            logged[#logged + 1] = string.format(format, ...)
        end
        _G.WwiseUtils = {
            trigger_unit_event = function(world, event, unit, node_id)
                native[#native + 1] = {
                    world = world, event = event, unit = unit, node_id = node_id,
                }
                return 41, "source", wwise_world
            end,
        }
        _G.Managers = {
            player = {},
            world = {
                has_world = function(_, name) return name == "level_world" end,
                world = function(_, name)
                    if name ~= "level_world" then error("unexpected world " .. tostring(name)) end
                    return level_world
                end,
                -- The retail accessor is a bare table read over worlds registered
                -- by create_world; an unregistered world simply returns nil.
                wwise_world = function(_, world)
                    if registered and world == level_world then return wwise_world end
                    return nil
                end,
            },
        }

        local channels = {}
        local om = {
            peer_resolver = {
                peer_player = function(_, peer_id)
                    if peer_id == "peer-rain" then return { player_unit = "owner-unit" } end
                    return nil, "player unavailable"
                end,
            },
        }
        install_wire({
            network_register = function(_, channel, handler) channels[channel] = handler end,
        }, { om = om })

        local ok, err = pcall(body, {
            om = om,
            channels = channels,
            native = native,
            logged = logged,
            level_world = level_world,
        })
        _G.Managers, _G.Unit, _G.WwiseUtils, _G.printf =
            saved.Managers, saved.Unit, saved.WwiseUtils, saved.printf
        if not ok then error(err, 0) end
    end

    local function find_line(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    H.test("CWV remote musket fire skips audio when no wwise world is registered", function()
        with_stub_engine(false, function(env)
            local played = env.om._old_musket_play_remote_fire(
                "peer-rain", "player_combat_weapon_rifle_fire", "identity_channel")
            H.equal(played, false)
            H.equal(#env.native, 0,
                "the native Wwise binding must not be reached without a registered world")
            H.truthy(find_line(env.logged,
                "[cwv:1211] remote fire audio skipped: no registered wwise world (world="),
                "the bail must emit its always-on needle")

            -- Bounded: a repeated skip does not spam the console.
            env.om._old_musket_play_remote_fire(
                "peer-rain", "player_combat_weapon_rifle_fire", "mode_channel")
            local skips = 0
            for _, line in ipairs(env.logged) do
                if line:find("[cwv:1211]", 1, true) then skips = skips + 1 end
            end
            H.equal(skips, 1)
            H.equal(#env.native, 0)
        end)
    end)

    H.test("CWV remote musket fire triggers the event on the registered level world", function()
        with_stub_engine(true, function(env)
            local played = env.om._old_musket_play_remote_fire(
                "peer-rain", "player_combat_weapon_rifle_fire", "identity_channel")
            H.equal(played, true)
            H.equal(#env.native, 1)
            H.equal(env.native[1].world, env.level_world)
            H.equal(env.native[1].event, "player_combat_weapon_rifle_fire")
            H.equal(env.native[1].unit, "owner-unit")
            H.equal(env.native[1].node_id, 0)
            H.equal(find_line(env.logged, "[cwv:1211]"), nil)

            -- The mode-channel receiver is the second entry wire; it must inherit
            -- the same guarded choke point rather than call Wwise itself.
            local handler = env.channels.cwv_old_musket_mode_v1
            H.truthy(handler, "the bounded mode channel must still register")
            handler("peer-rain", 1, "fire", "slot_ranged",
                "player_combat_weapon_rifle_fire", "bid-old-musket")
            H.equal(#env.native, 2)
            H.equal(env.native[2].world, env.level_world)

            -- Unresolvable peer fails closed with no native call.
            H.equal(env.om._old_musket_play_remote_fire(
                "peer-unknown", "player_combat_weapon_rifle_fire", "rt"), false)
            H.equal(#env.native, 2)
        end)
    end)

    H.test("CWV in-keep regression proves a registered wwise world resolves", function()
        H.truthy(source:find("_om._old_musket_wwise_world = registered_level_world", 1, true))
        H.truthy(source:find("remote fire audio resolved a world Wwise never registered", 1, true))
        H.truthy(source:find("remote fire acceptor must fail closed on an unresolvable peer", 1, true))
    end)
end
