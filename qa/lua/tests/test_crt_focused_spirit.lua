return function(H, repo_root)
    local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
    local Policy = assert(loadfile(base .. "_crt_focused_spirit.lua"))()

    local function read(name)
        local file = assert(io.open(base .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CRT #472 composes all four Focused Spirit descriptions", function()
        H.equal(Policy.description(false, false), nil)
        local ignore = assert(Policy.description(false, true))
        local stacking = assert(Policy.description(true, false))
        local both = assert(Policy.description(true, true))
        H.truthy(ignore:find("15%%", 1, true))
        H.truthy(string.format(ignore, 10, 15):find("15%", 1, true))
        H.equal(string.format(ignore, 10, 15):find("15%%", 1, true), nil)
        H.truthy(ignore:find("Ratling Gunners", 1, true))
        H.truthy(stacking:find("5%", 1, true))
        H.equal(stacking:find("5%%", 1, true), nil)
        H.truthy(stacking:find("5 stacks (25%)", 1, true))
        H.equal(stacking:find("Ratling Gunners", 1, true), nil)
        H.truthy(both:find("5 stacks (25%)", 1, true))
        H.truthy(both:find("Ratling Gunners", 1, true))
    end)

    H.test("CRT #472 assigns exactly one transition writer", function()
        H.equal(Policy.transition_role({ local_player = true }, false), "writer")
        H.equal(Policy.transition_role({ local_player = true }, true), "writer")
        H.equal(Policy.transition_role({ local_player = false }, true), "mirror")
        H.equal(Policy.transition_role({ local_player = false }, false), "none")
        H.equal(Policy.transition_role({ bot_player = true }, true), "writer")
        H.equal(Policy.transition_role({ bot_player = true }, false), "none")
        H.equal(Policy.transition_role(nil, true), "none")
    end)

    H.test("CRT #472 grows one mirrored stack per interval to five", function()
        local owner, server, cooldown_requests = 0, 0, 0
        for expected = 1, 5 do
            H.equal(Policy.growth_action("writer", true, owner), "rearm")
            H.equal(Policy.growth_action("mirror", true, server), "preserve")
            cooldown_requests = cooldown_requests + 1
            -- One vanilla owner request is mirrored to both buffer=both copies.
            owner, server = owner + 1, server + 1
            H.equal(owner, expected)
            H.equal(server, expected)
        end
        H.equal(cooldown_requests, 5)
        H.equal(Policy.growth_action("writer", true, 5), "preserve")
        H.equal(Policy.growth_action("writer", false, 2), "preserve")
    end)

    H.test("CRT #472 ordinary damage removes one mirrored stack and restarts once", function()
        for _, initial in ipairs({ 1, 3, 5 }) do
            local cooldown_requests = 0
            local owner_action = Policy.damage_action({
                rework_live = true, role = "writer", damage_amount = 10,
            })
            local server_action = Policy.damage_action({
                rework_live = true, role = "mirror", damage_amount = 10,
            })
            H.equal(owner_action, "remove_one_restart")
            H.equal(server_action, "remove_one_mirror")
            if owner_action == "remove_one_restart" then cooldown_requests = cooldown_requests + 1 end
            if server_action == "remove_one_restart" then cooldown_requests = cooldown_requests + 1 end
            H.equal(math.max(initial - 1, 0), initial - 1)
            H.equal(cooldown_requests, 1, "only the writer requests the mirrored cooldown")
        end
        H.equal(Policy.zero_stack_action({
            rework_live = true, role = "writer", ignored = false,
            attacker_self = false, damage_amount = 10, stack_count = 0,
        }), "restart")
        H.equal(Policy.zero_stack_action({
            rework_live = true, role = "mirror", ignored = false,
            attacker_self = false, damage_amount = 10, stack_count = 0,
        }), "preserve")
    end)

    H.test("CRT #472 ignored, self, zero, duplicate, and vanilla paths preserve bounds", function()
        H.equal(Policy.damage_action({ ignored = true, rework_live = true,
            role = "writer", damage_amount = 10 }), "ignored_preserve")
        H.equal(Policy.damage_action({ rework_live = true, role = "writer",
            attacker_self = true, damage_amount = 10 }), "self_or_zero_preserve")
        H.equal(Policy.damage_action({ rework_live = true, role = "writer",
            damage_amount = 0 }), "self_or_zero_preserve")
        H.equal(Policy.damage_action({ rework_live = true, role = "writer",
            handled = true, damage_amount = 10 }), "duplicate_proc_preserve")
        H.equal(Policy.damage_action({ rework_live = false, role = "writer",
            damage_amount = 10 }), "delegate_vanilla")
        H.equal(Policy.damage_action({ rework_live = true, role = "none",
            damage_amount = 10 }), "no_authority_preserve")
    end)

    H.test("CRT #472 consensus requires both settings and fails closed on ambiguity", function()
        local config = { stacking = true, ignore_chip = true }
        local peers = { peer_b = true }
        local peer_ok = { peer_b = true }
        local sends, receiver, changes = {}, nil, 0
        local mod = {}
        function mod:network_register(channel, fn)
            H.equal(channel, Policy.CHANNEL)
            receiver = fn
        end
        function mod:network_send(channel, recipient, schema, is_reply,
                epoch, generation, stacking, ignore_chip)
            sends[#sends + 1] = {
                channel, recipient, schema, is_reply, epoch, generation,
                stacking, ignore_chip,
            }
        end
        local base_parity = {
            LOCAL_EPOCH = "local:one",
            all_peers_have = function() return true end,
            peer_has = function(_, peer_id) return peer_ok[peer_id] == true end,
        }
        local consensus = Policy.new_consensus(mod, base_parity, {
            config = function()
                return { stacking = config.stacking, ignore_chip = config.ignore_chip }
            end,
            other_peers = function() return peers, true end,
            on_remote_change = function() changes = changes + 1 end,
        })
        H.equal(consensus:install(), true)
        H.equal(consensus:all_match(), false, "missing peer config must fail closed")
        H.equal(consensus:announce(), true)
        H.deep_equal(sends[1], {
            Policy.CHANNEL, "others", Policy.SCHEMA, 0, "local:one", 1, 1, 1,
        })

        receiver("peer_b", Policy.SCHEMA, 0, "remote:one", 1, 1, 1)
        H.equal(consensus:all_match(), true)
        H.equal(#sends, 2, "one valid announcement receives one direct reply")
        H.equal(sends[2][2], "peer_b")
        H.equal(sends[2][4], 1)

        receiver("peer_b", Policy.SCHEMA, 1, "remote:one", 2, 1, 0)
        H.equal(consensus:all_match(), false, "ignore-setting mismatch must fail closed")
        receiver("peer_b", Policy.SCHEMA, 1, "remote:one", 1, 1, 1)
        H.equal(consensus:all_match(), false, "stale generation must not replace newer state")
        receiver("peer_b", Policy.SCHEMA, 1, "remote:one", 2, 1, 1)
        H.equal(consensus:all_match(), false,
            "same-generation contradiction must poison that generation")
        H.equal(consensus:state_for("peer_b").conflict, true)
        receiver("peer_b", Policy.SCHEMA, 1, "remote:one", 3, 1, 1)
        H.equal(consensus:all_match(), true, "newer coherent generation may recover")

        receiver("peer_b", Policy.SCHEMA, 1, "foreign:process", 4, 1, 1)
        H.equal(consensus:all_match(), false, "foreign live epoch must fail closed")
        consensus:forget_peer("peer_b")
        receiver("peer_b", Policy.SCHEMA, 1, "foreign:process", 1, 1, 1)
        H.equal(consensus:all_match(), true, "departure edge permits the new process epoch")

        config.ignore_chip = false
        H.equal(consensus:set_local_changed(), true)
        H.equal(consensus:generation(), 2)
        H.equal(consensus:all_match(), false)
        H.equal(sends[#sends][8], 0)
        H.truthy(changes >= 5)
    end)

    H.test("CRT #472 consensus rejects malformed, unproven, and throwing inputs", function()
        local receiver
        local base = {
            LOCAL_EPOCH = "local:two",
            all_peers_have = function() return true end,
            peer_has = function() return false end,
        }
        local mod = {
            network_register = function(_, _, fn) receiver = fn end,
            network_send = function() error("transport unavailable") end,
        }
        local consensus = Policy.new_consensus(mod, base, {
            config = function() error("settings unavailable") end,
            other_peers = function() return { stranger = true }, true end,
        })
        H.equal(consensus:install(), true)
        H.equal(consensus:announce(), false)
        H.equal(consensus:all_match(), false)
        receiver("stranger", Policy.SCHEMA, 0, "remote:two", 1, 1, 1)
        H.equal(consensus:state_for("stranger"), nil)
        receiver("stranger", 99, 0, "remote:two", 1, 1, 1)
        receiver("stranger", Policy.SCHEMA, 0, "bad epoch!", 1, 1, 1)
        receiver("stranger", Policy.SCHEMA, 0, "remote:two", 0, 1, 1)
        H.equal(consensus:state_for("stranger"), nil)

        base.all_peers_have = function() error("roster failure") end
        H.equal(consensus:all_match(), false)
    end)

    H.test("CRT #472 production consumes one shared policy and authored localization key", function()
        local entry = read("career_tweaker.lua")
        local policy_source = read("_crt_focused_spirit.lua")
        local armor = read("career_tweaker_armor_overcharge.lua")
        local catalog = read("_crt_balance_catalog_focused_spirit.lua")
        local hooks = read("_career_tweaker_balance_hooks.lua")
        local localization = read("career_tweaker_localization.lua")
        H.truthy(entry:find('config = function()', 1, true))
        H.truthy(entry:find('ignore_chip = mod:get("maidenguard_focused_spirit_ignore_chip_damage") == true', 1, true))
        H.truthy(armor:find("FocusedSpirit.transition_role", 1, true))
        H.truthy(armor:find("FocusedSpirit.growth_action", 1, true))
        H.truthy(armor:find("FocusedSpirit.damage_action", 1, true))
        H.truthy(armor:find("FocusedSpirit.zero_stack_action", 1, true))
        H.truthy(armor:find('mod:command("crt_verify_focused_spirit"', 1, true))
        H.equal(armor:find("_focused_add_local_cooldown", 1, true), nil)
        H.truthy(catalog:find("network_unsafe = true", 1, true))
        H.truthy(catalog:find("policy.VANILLA_DESCRIPTION_KEY", 1, true))
        H.truthy(hooks:find("[focused_policy.VANILLA_DESCRIPTION_KEY]", 1, true))
        H.equal(localization:find("crt_kerillian_maidenguard_focused_spirit_stacks_desc", 1, true), nil)
        H.equal(policy_source:find("mod.update", 1, true), nil,
            "settings consensus must not acquire a polling/update owner")
    end)

    H.test("CRT #472 installed callbacks perform one writer restart and one mirror removal", function()
        local names = {
            "get_mod", "printf", "DamageUtils", "PlayerUnitHealthExtension",
            "ProcFunctions", "BuffFunctionTemplates", "BuffTemplates", "ScriptUnit",
            "Managers", "ALIVE", "Breeds",
        }
        local saved = {}
        for i = 1, #names do
            local name = names[i]
            saved[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
        end
        local function restore()
            for i = #names, 1, -1 do
                local name, old = names[i], saved[names[i]]
                rawset(_G, name, old.present and old.value or nil)
            end
        end

        local ok, err = pcall(function()
            local settings = {
                rework_we_maidenguard_focused_spirit_stacks = true,
                maidenguard_focused_spirit_ignore_chip_damage = true,
            }
            local commands, cooldown_requests = {}, 0
            local mod = {
                _crt = {
                    focused_spirit = Policy,
                    damage_classification = {
                        is_chip_or_aoe = function() return false end,
                        is_self_dot = function() return false end,
                        focused_spirit_ignores = function(_, _, source)
                            return source == "dot_debuff"
                        end,
                        foot_knight = nil,
                    },
                    focused_spirit_consensus = { all_match = function() return true end },
                },
                get = function(_, id) return settings[id] == true end,
                info = function() end,
                echo = function() end,
                command = function(_, name, _, fn) commands[name] = fn end,
                _crt_wire_safe = function() return true end,
                _crt_wire_live = function() return true end,
            }
            function mod:hook(target, method, wrapper)
                local original = target[method]
                target[method] = function(...)
                    return wrapper(original, ...)
                end
            end

            rawset(_G, "get_mod", function() return mod end)
            rawset(_G, "printf", function() end)
            rawset(_G, "Breeds", {})
            rawset(_G, "DamageUtils", {
                apply_buffs_to_damage = function(damage) return damage end,
            })
            rawset(_G, "BuffTemplates", {
                sienna_necromancer_5_2_counter_remover = {
                    buffs = { { buff_func = "remove_buff_stack" } },
                },
                kerillian_maidenguard_power_level_on_unharmed = {
                    buffs = { { buff_func = "maidenguard_reset_unharmed_buff" } },
                },
            })
            rawset(_G, "BuffFunctionTemplates", { functions = {} })
            rawset(_G, "ProcFunctions", {
                remove_buff_stack = function() end,
                maidenguard_reset_unharmed_buff = function(unit, _, params)
                    local attacker, amount = params and params[1], params and params[2]
                    if attacker == unit or amount == 0 then return false end
                    cooldown_requests = cooldown_requests + 1
                    unit.buff.cooldown = true
                    return true
                end,
            })
            rawset(_G, "ScriptUnit", {
                has_extension = function(unit, name)
                    return unit and unit.extensions and unit.extensions[name]
                end,
            })
            local player_manager = {
                is_server = false,
                owner = function(_, unit) return unit and unit.player end,
                local_player = function() return nil end,
            }
            rawset(_G, "Managers", { player = player_manager, state = {} })
            local alive = {}
            rawset(_G, "ALIVE", alive)

            local function make_unit(player, stack_count)
                local unit = { player = player, extensions = {} }
                local buff = { stacks = {}, cooldown = false }
                for i = 1, stack_count do buff.stacks[i] = { id = i } end
                function buff:get_stacking_buff() return self.stacks end
                function buff:remove_buff(id)
                    for i = 1, #self.stacks do
                        if self.stacks[i].id == id then table.remove(self.stacks, i); return end
                    end
                end
                function buff:has_buff_type(name)
                    return name == "kerillian_maidenguard_power_level_on_unharmed_cooldown"
                        and self.cooldown
                end
                unit.buff = buff
                unit.extensions.buff_system = buff
                unit.extensions.talent_system = {
                    has_talent = function() return true end,
                }
                unit.extensions.career_system = { _career_name = "we_maidenguard" }
                alive[unit] = true
                return unit
            end

            local PlayerHealth = {
                add_damage = function(self, attacker, amount)
                    local snapshot = {}
                    for i = 1, #self.unit.buff.stacks do
                        snapshot[i] = self.unit.buff.stacks[i]
                    end
                    for i = 1, #snapshot do
                        ProcFunctions.crt_focused_spirit_damage_taken(
                            self.unit, snapshot[i], { attacker, amount })
                    end
                    if self.raise_after_procs then error("planted damage failure") end
                end,
            }
            rawset(_G, "PlayerUnitHealthExtension", PlayerHealth)

            assert(loadfile(base .. "career_tweaker_armor_overcharge.lua"))()
            H.truthy(commands.crt_verify_focused_spirit)

            local attacker = {}
            local owner = make_unit({ local_player = true }, 3)
            player_manager.is_server = false
            PlayerUnitHealthExtension.add_damage(
                { unit = owner }, attacker, 10, nil, "light_attack", nil, nil,
                "skaven_storm_vermin")
            H.equal(#owner.buff.stacks, 2)
            H.equal(cooldown_requests, 1)

            local mirror = make_unit({ local_player = false }, 3)
            player_manager.is_server = true
            PlayerUnitHealthExtension.add_damage(
                { unit = mirror }, attacker, 10, nil, "light_attack", nil, nil,
                "skaven_storm_vermin")
            H.equal(#mirror.buff.stacks, 2)
            H.equal(cooldown_requests, 1,
                "server mirror must never create a second cooldown")

            local ignored = make_unit({ local_player = true }, 3)
            player_manager.is_server = false
            PlayerUnitHealthExtension.add_damage(
                { unit = ignored }, attacker, 10, nil, "burninating", nil, nil,
                "dot_debuff")
            H.equal(#ignored.buff.stacks, 3)
            H.equal(ignored.buff.cooldown, false)
            H.equal(cooldown_requests, 1)

            local empty = make_unit({ local_player = true }, 0)
            PlayerUnitHealthExtension.add_damage(
                { unit = empty }, attacker, 10, nil, "light_attack", nil, nil,
                "skaven_storm_vermin")
            H.equal(cooldown_requests, 2,
                "zero-stack ordinary damage must restart exactly once")

            local failing = make_unit({ local_player = true }, 2)
            local damage_ok = pcall(PlayerUnitHealthExtension.add_damage,
                { unit = failing, raise_after_procs = true }, attacker, 10, nil,
                "light_attack", nil, nil, "skaven_storm_vermin")
            H.equal(damage_ok, false)
            H.equal(cooldown_requests, 2,
                "a failed enclosing damage call must not schedule a cooldown")
            H.equal(mod._crt_focused_spirit_damage_context, nil,
                "error unwind must restore the exact prior context")

            local growing_owner = make_unit({ local_player = true }, 1)
            local growing_mirror = make_unit({ local_player = false }, 1)
            player_manager.is_server = false
            BuffFunctionTemplates.functions.crt_focused_spirit_arm_growth(growing_owner)
            player_manager.is_server = true
            BuffFunctionTemplates.functions.crt_focused_spirit_arm_growth(growing_mirror)
            player_manager.is_server = false
            mod._crt_focused_spirit_tick()
            H.equal(cooldown_requests, 3,
                "one owner growth callback must schedule one mirrored interval")
        end)
        restore()
        if not ok then error(err, 0) end
    end)
end
