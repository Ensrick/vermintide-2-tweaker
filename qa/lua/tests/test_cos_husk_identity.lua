return function(H, repo_root)
    local module_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_identity.lua"
    local policy = assert(loadfile(module_path))()

    H.test("Cosmetics #698 career-scoped entries fail closed and preserve bot owners", function()
        local entry = policy.new_entry("armor", "gk_purpure", "gk_base", nil,
            "es_questingknight")
        H.equal(entry.wearer_career, "es_questingknight")
        H.equal(policy.entry_matches_career(entry, "es_questingknight"), true)

        local ok, why = policy.entry_matches_career(entry, "es_knight")
        H.equal(ok, false)
        H.truthy(why:find("career%-mismatch") ~= nil)
        H.equal(policy.entry_matches_career({ kind = "armor" }, "es_knight"), false)
        H.equal(policy.entry_matches_career(entry, nil), false)
        H.equal(policy.transport_career_valid("es_knight", nil), true)
        H.equal(policy.transport_career_valid("es_knight", "es_questingknight"), false)

        local bot_store = { peer = { slot_skin = entry } }
        local removed, reason = policy.invalidate_for_career(
            bot_store, "peer", "es_knight", false)
        H.equal(removed, 0)
        H.equal(reason, "non-human-owner-alias")
        H.equal(bot_store.peer.slot_skin, entry)
    end)

    H.test("Cosmetics #698 spawn monitor invalidates humans without consuming bot aliases", function()
        local function player(controlled, career)
            return {
                peer_id = "peer",
                is_player_controlled = function() return controlled end,
                career = career,
            }
        end
        local function deps(store)
            return {
                bridge = { registered = true }, store = store,
                persistence = {
                    _career_name_for_player = function(owner) return owner.career end,
                },
                score_identity = {
                    should_purge_mismatch = function(value) return value == true end,
                },
                script_unit = { has_extension = function() return nil end },
                unit_api = { alive = function() return true end },
                managers = function()
                    return { player = { owner = function(_, unit) return unit.owner end } }
                end,
                profiles = function() return {} end,
                resolve_variant = function() return nil end,
                chars_compatible = function() return true end,
                purge = function(cache, peer_id, slot) cache[peer_id][slot] = nil end,
                debug = function() end, warning = function() end, print = function() end,
            }
        end

        local stale = policy.new_entry("armor", "gk_purpure", "gk_base", nil,
            "es_questingknight")
        local human_store = { peer = { slot_skin = stale } }
        policy.make_spawn_monitor(deps(human_store))({
            owner = player(true, "es_knight"),
        })
        H.equal(human_store.peer, nil)

        local bot_store = { peer = { slot_skin = stale } }
        policy.make_spawn_monitor(deps(bot_store))({
            owner = player(false, "es_knight"),
        })
        H.equal(bot_store.peer.slot_skin, stale)
    end)

    H.test("Cosmetics #698 career change invalidates remote material replay", function()
        local store = { peer = {
            slot_skin = policy.new_entry("armor", "gk_purpure", "gk_base", nil,
                "es_questingknight"),
            slot_hat = policy.new_entry("hat", "gk_hat", "gk_hat_base", nil,
                "es_questingknight"),
            slot_melee = policy.new_entry("offhand", "fk_shield", "fk_base",
                "left_hand_unit", "es_knight"),
            legacy = { kind = "armor", armoury_key = "unstamped" },
        } }
        local removed, reason, slots = policy.invalidate_for_career(
            store, "peer", "es_knight", true)
        H.equal(removed, 3)
        H.equal(reason, "career-invalidated")
        H.deep_equal(slots, { "legacy", "slot_hat", "slot_skin" })
        H.equal(store.peer.slot_melee.wearer_career, "es_knight")
        H.equal(store.peer.slot_skin, nil)
    end)

    H.test("Cosmetics #698 human wearer is local_player_id-aware, never peer-only", function()
        -- Controlled human -> human.
        local human = { peer_id = "host", _local_player_id = 1,
            is_player_controlled = function() return true end }
        local ok, reason = policy.wearer_is_human(human)
        H.equal(ok, true)
        H.equal(reason, "player-controlled")

        -- A host bot shares the host peer but is local_player_id 2..4 and
        -- not controlled -> NOT human (correctly skipped).
        local bot = { peer_id = "host", _local_player_id = 3,
            is_player_controlled = function() return false end }
        local bot_ok, bot_reason = policy.wearer_is_human(bot)
        H.equal(bot_ok, false)
        H.equal(bot_reason, "non-human-owner-alias")

        -- The regression: a real human whose controlled flag is transiently
        -- nil during spawn/sync is rescued by local_player_id 1 (bots never
        -- own slot 1), so the human is no longer skipped as an "alias".
        local flaky_human = { peer_id = "host", _local_player_id = 1,
            is_player_controlled = function() return nil end }
        local fh_ok, fh_reason = policy.wearer_is_human(flaky_human)
        H.equal(fh_ok, true)
        H.equal(fh_reason, "local-player-1")

        -- local_player_id reads either a method or a plain field, nil-safe.
        H.equal(policy.local_player_id({ local_player_id = function() return 2 end }), 2)
        H.equal(policy.local_player_id({ _local_player_id = 4 }), 4)
        H.equal(policy.local_player_id(nil), nil)
    end)

    H.test("Cosmetics #698 host client and husk paths carry one career identity", function()
        local entry_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local f = assert(io.open(entry_path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find("local COS_RPC_SCHEMA = 2", 1, true))
        H.truthy(source:find("wearer_career  = wearer_career", 1, true))
        H.truthy(source:find("wearer_career  = entry.wearer_career", 1, true))
        H.truthy(source:find("local wearer_career = payload.wearer_career", 1, true))
        H.truthy(source:find("invalidate_for_career", 1, true))
        H.truthy(source:find("entry_matches_career", 1, true))
        H.truthy(source:find("make_spawn_monitor", 1, true))
        H.truthy(source:find("career_name = self and self._career_name", 1, true))
        local runtime_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua"
        local runtime_file = assert(io.open(runtime_path, "rb"))
        local runtime_source = runtime_file:read("*a")
        runtime_file:close()
        H.truthy(runtime_source:find("issue698_husk_career_identity", 1, true))
    end)
end
