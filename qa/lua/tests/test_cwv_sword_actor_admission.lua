-- SOURCE-ONLY prepared suite. Native dependency shapes are simulated; the
-- construction/retained authority/admission/runtime/world wrapper/queue are real chunks.
-- This is actor admission coverage, not native GearUtils/game/animation proof.
return function(H, root)
    local dir = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local function load(name, env)
        local chunk = assert(loadfile(dir .. name .. ".lua"))
        if env then setfenv(chunk, env) end
        return chunk()
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function fixture(policy_env, construction)
        policy_env = policy_env or setmetatable({}, { __index = _G })
        policy_env._G = policy_env
        local P, Actor = load("_cwv_combat_styles", policy_env), load("_cwv_style_actor_admission")
        H.equal(P.member("es_1h_sword"), "one_handed_swords", "real authored catalogue required")
        H.equal(P.member("we_1h_sword"), "one_handed_swords")
        local s = { local_pi = 7, local_ci = 1, remote_pi = 7, remote_ci = 1,
            saved = { schema = 1, items = { sword_id = "elven" } }, sent = {}, writes = 0, wields = 0 }
        s.careers = {
            es_native = { name = "es_native", profile_name = "empire_soldier" },
            we_native = { name = "we_native", profile_name = "wood_elf" },
            other = { name = "other", profile_name = "witch_hunter" },
        }
        s.profiles = {
            [7] = { display_name = "empire_soldier", careers = { s.careers.es_native } },
            [12] = { display_name = "wood_elf", careers = { s.careers.we_native } },
            [19] = { display_name = "witch_hunter", careers = { s.careers.other } },
        }
        s.unit, s.remote_unit = {}, {}
        s.item = { name = "es_1h_sword", backend_id = "sword_id" }
        s.remote_item = { name = "es_1h_sword" }
        s.player_methods = {
            profile_index = function(self) H.equal(self, s.player); return s.local_pi end,
            career_index = function(self) H.equal(self, s.player); return s.local_ci end,
        }
        s.player_methods.__index = s.player_methods
        s.player = setmetatable({ peer_id = "local", _local_player_id = 1, player_unit = s.unit },
            s.player_methods)
        s.remote_player = { peer_id = "remote", _local_player_id = 1, player_unit = s.remote_unit }
        s.equipment = { slots = { slot_melee = { item_data = s.item } }, wielded_slot = "slot_melee" }
        s.inventory = { _unit = s.unit, player = s.player, _career_name = "es_native", is_bot = false,
            _equipment = s.equipment, equipment = function() return s.equipment end }
        s.remote_equipment = { slots = { slot_melee = { item_data = s.remote_item } }, wielded_slot = "slot_melee" }
        s.remote_inventory = { _unit = s.remote_unit, _equipment = s.remote_equipment, wielded_slot = "slot_melee",
            wield = function() s.wields = s.wields + 1 end }
        s.player_manager_methods = {
            local_player = function() return s.player end,
            owner = function(_, unit) if unit == s.unit then if s.owner_missing then return nil end; return s.player end
                if unit == s.remote_unit then return s.remote_player end end,
            player_from_peer_id = function(_, peer) if peer == "remote" then return s.remote_player end
                if peer == "local" then return s.player end end,
        }
        s.player_manager_methods.__index = s.player_manager_methods
        s.managers = { player = setmetatable({}, s.player_manager_methods),
            state = { network = { profile_synchronizer = {
            profile_by_peer = function(_, peer, id)
                H.equal(id, 1)
                if peer == "remote" then return s.remote_pi, s.remote_ci end
                if peer == "local" then return s.local_pi, s.local_ci end
            end,
        } } } }
        s.script = {
            extension = function(unit) return unit == s.unit and s.inventory or unit == s.remote_unit and s.remote_inventory or nil end,
            has_extension = function(unit) return unit == s.unit and s.inventory or unit == s.remote_unit and s.remote_inventory or nil end,
        }
        s.actor = Actor.bind({ profiles = function() return s.profiles end, careers = function() return s.careers end,
            managers = function() return s.managers end, peer_resolver = load("_cwv_peer_resolver"),
            inventory_for_unit = s.script.has_extension,
            find_profile_index = function(name) for pi, row in pairs(s.profiles) do if row.display_name == name then return pi end end end })
        s.coalescer, s.rewield = load("_cwv_rewield_coalescer"), load("_cwv_style_rewield")
        s.units = { alive = function(unit) return unit ~= nil end }
        s.mod = { get = function() return s.saved end, set = function(_, _, value) s.writes = s.writes + 1; s.saved = value end,
            network_send = function(_, ...) s.sent[#s.sent + 1] = pack(...); return true end }
        local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_construction_harness.lua"))()
        local c = construction or F.new(H, root)
        s.construction, s.weapons = c, c.env.Weapons
        policy_env.Weapons, policy_env.Managers = s.weapons, s.managers
        c.state.combat_style_policy = P
        local file = assert(io.open(dir .. "character_weapon_variants.lua", "rb"))
        local entry = file:read("*a"); file:close()
        local first = '_om.sword_family = mod:dofile("scripts/mods/character_weapon_variants/_cwv_sword_family").install(mod, {'
        local at = assert(entry:find(first, 1, true))
        H.equal(entry:find(first, at + 1, true), nil, "one actual Sword owner installation")
        local finish = assert(entry:find("\n})", at, true)) + 2
        local bootstrap = c.T.run("return function(mod, _om, _core_template_construction, _cwv_profile_graph, "
            .. "_cwv_network_lookup, _cwv_career_envelope, _career_weapon_actions, _rt_register)\n"
            .. entry:sub(at, finish) .. "\nreturn _om.sword_family end", c.env, "actual-entry-Sword-family-bootstrap")
        s.sword_family = bootstrap({
            dofile = function(_, name) return load(assert(name:match("([^/]+)$"))) end,
        }, c.state, c.core, c.graph, c.helper, c.career_envelope, load("_lib_career_weapon_actions"),
            function(name, fn)
                if name == "issue645_reciprocal_one_handed_sword_family" then s.family_check = fn
                elseif name == "issue645_mace_on_kruber_sword_family" then s.mace_check = fn
                else error("unexpected family check: " .. tostring(name)) end
            end)
        H.equal(s.family_check(), nil, "real serial construction and retained owner required")
        local before_expression = assert(entry:match("\n\t\tbefore_style_commit = ([^\n]+),\n"))
        local before_commit = c.T.run("return function(_om) return " .. before_expression .. " end",
            c.env, "actual-entry-before-style-commit-value")(c.state)
        s.runtime = P.install(s.mod, { actor_admission = s.actor, sword_family = s.sword_family,
            before_style_commit = before_commit,
            local_equipment = function() return s.inventory end,
            peer_for_owner = function(unit) return unit == s.remote_unit and "remote" or unit == s.unit and "local" or nil end,
            acquire_style_resource = function(_, callback) s.complete = callback; return true end,
            rebuild_remote = function(peer, slot, family, style, verdict, descriptor)
                return s.rewield.queue_rebuild(s.rewield_deps, peer, slot, family, style, verdict, descriptor)
            end, rewield = s.rewield })
        s.rewield_deps = { policy = P, coalescer = s.coalescer, managers = s.managers,
            unit_api = s.units, script_unit = s.script, probe_state = {}, printf = function() end,
            peer_player = function() return s.remote_player end,
            item_key = function(item) return item.name end,
            actor_admitted = function(peer, slot, key, family, style)
                return s.runtime:queued_style_admitted(peer, slot, key, family, style)
            end }
        s.family = P.member("es_1h_sword")
        s.ui_installer = load("_cwv_combat_style_loadout_ui", policy_env)
        s.policy, s.Actor = P, Actor
        return s
    end
    H.test("645 native class-shaped methods are inherited and throwing lookup or invocation refuses", function()
        local s = fixture()
        H.equal(rawget(s.player, "profile_index"), nil)
        H.equal(rawget(s.player, "career_index"), nil)
        H.equal(rawget(s.managers.player, "owner"), nil)
        H.truthy(s.runtime:describe(s.item), "real inherited methods must admit the canonical actor")
        H.equal(s.actor:inventory_profile(s.inventory), "empire_soldier")
        for _, fault in ipairs({ "profile lookup", "profile call", "career call", "owner lookup", "owner call" }) do
            local f = fixture()
            if fault == "profile lookup" then
                setmetatable(f.player, { __index = function() error("This object has been destroyed", 0) end })
            elseif fault == "profile call" then
                f.player_methods.profile_index = function() error("destroyed profile method", 0) end
            elseif fault == "career call" then
                f.player_methods.career_index = function() error("destroyed career method", 0) end
            elseif fault == "owner lookup" then
                setmetatable(f.managers.player, { __index = function() error("This object has been destroyed", 0) end })
            else
                f.player_manager_methods.owner = function() error("destroyed owner method", 0) end
            end
            H.equal(f.actor:inventory_profile(f.inventory), nil, fault)
            H.equal(f.runtime.store.items.sword_id, "elven", fault)
            H.equal(f.writes, 0, fault)
        end
    end)
    H.test("645 actor gate uses exact native profile/career membership, never can_wield", function()
        local s = fixture()
        H.equal(s.Actor.admitted("es_1h_sword", "empire_soldier"), true)
        H.equal(s.Actor.admitted("we_1h_sword", "wood_elf"), true)
        for _, profile in ipairs({ "wood_elf", "witch_hunter", "es_fake" }) do
            H.equal(s.Actor.admitted("es_1h_sword", profile), false)
        end
        H.equal(s.Actor.admitted("es_1h_sword", nil), false)
        H.equal(s.Actor.admitted("es_2h_sword", nil), true)
        s.item.can_wield = { "we_native", "other", "es_fake" }
        s.local_pi = 12
        H.equal(s.runtime:describe(s.item), nil)
        H.equal(s.runtime.store.items.sword_id, "elven")
        s.local_pi = 7
        H.truthy(s.runtime:describe(s.item))
        s.profiles[7].careers[1] = { name = "es_native", profile_name = "empire_soldier" }
        H.equal(s.runtime:describe(s.item), nil, "same-shaped replacement is not canonical membership")
    end)
    H.test("645 selected UI actor is independent of viewer and re-resolves exact window/content", function()
        local s = fixture()
        s.local_pi = 12
        local window = { hero_name = "empire_soldier", career_index = 1 }
        local actor = s.runtime:loadout_actor(window)
        H.truthy(s.runtime:describe(s.item, nil, actor))
        window.hero_name = "wood_elf"
        H.equal(s.runtime:describe(s.item, nil, actor), nil)
        local content = { profile_index = 7, career_index = 1 }
        local console_actor = s.runtime:console_actor(content)
        H.truthy(s.runtime:describe(s.item, nil, console_actor))
        content.profile_index = 19
        H.equal(s.runtime:describe(s.item, nil, console_actor), nil)
        H.equal(s.runtime:describe(s.item, nil, s.runtime:loadout_actor({})), nil)
        H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0)
    end)
    H.test("645 reciprocal Elven physical item admits only actual wood-elf actors", function()
        local s = fixture()
        s.item.name, s.remote_item.name = "we_1h_sword", "we_1h_sword"
        s.local_pi, s.remote_pi, s.inventory._career_name = 12, 12, "we_native"
        s.runtime.store.items.sword_id = "empire"
        H.equal(s.runtime:describe(s.item).style_id, "empire")
        H.equal(s.runtime:remote_actor_admitted("remote", "slot_melee", "we_1h_sword"), true)
        s.local_pi, s.remote_pi = 7, 7
        H.equal(s.runtime:describe(s.item), nil)
        H.equal(s.runtime:remote_actor_admitted("remote", "slot_melee", "we_1h_sword"), false)
        H.equal(s.runtime.store.items.sword_id, "empire"); H.equal(s.writes, 0)
    end)
    H.test("645 async selected-actor change keeps saved preference dormant and never rebuilds", function()
        local s, changed = fixture(), nil
        local window = { hero_name = "empire_soldier", career_index = 1 }
        H.equal(s.runtime:request_item_style(s.item, nil, "empire", "actor-test", true,
            function(value) changed = value end, s.runtime:loadout_actor(window)), true)
        H.equal(type(s.complete), "function")
        window.hero_name = "wood_elf"
        s.complete(true)
        H.equal(changed, false); H.equal(s.runtime.pending.sword_id, nil)
        H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0); H.equal(s.wields, 0)
        H.equal(s.runtime:set_item_style(s.item, nil, "empire", "unknown", false, function() return nil end), false)
        H.equal(s.runtime.store.items.sword_id, "elven")
    end)
    local function world_hook(s)
        local hooks, count = {}, 0
        local env = setmetatable({ printf = function() end }, { __index = _G })
        local mod = { hook = function(_, class, name, fn)
            H.equal(class, "GearUtils"); H.equal(name, "create_equipment")
            count = count + 1; hooks.create = fn
        end }
        load("_cwv_world_equipment_owner", env)(mod, { om = {
            style_actor_admission = s.actor,
            _cwv_transform_consumers = { world = function() return nil end },
            _cwv_key_for_item = function() error("intentional contained post-native auxiliary") end,
        }, dbg = function() end, resolve_field = function() end, apply_cwv_hand_transform = function() end })
        H.equal(count, 1)
        return hooks.create
    end
    H.test("645 installed world wrapper admits initial exact inventory actor before PM map/slot", function()
        local s = fixture()
        local prior = _G.Weapons
        local ok, err = pcall(function()
            local native, custom, calls = s.weapons.one_handed_swords_template_1, s.weapons.cwv_645_elven_sword_style, 0
            _G.Weapons = s.weapons
            s.equipment.slots.slot_melee = nil; s.owner_missing = true; s.player.player_unit = nil
            local hook = world_hook(s)
            local result = {}
            -- Source-qualified native call sequence: GearUtils line9 performs
            -- BackendUtils template lookup inside this existing wrapper. This
            -- callback drives the actual style resolver, not the native body.
            local values = pack(hook(function(_, slot, item, _, unit, bot, _, _, _, _, _, career)
                calls = calls + 1
                H.equal(slot, "slot_melee"); H.equal(item, s.item); H.equal(unit, s.unit)
                H.equal(bot, false); H.equal(career, "es_native")
                H.equal(s.runtime:resolve_template(item), custom, "initial native actor false fact must select retained custom template")
                return result, nil, 17, nil
            end, {}, "slot_melee", s.item, {}, s.unit, false, nil, nil, nil, nil, nil, "es_native"))
            H.equal(calls, 1); H.equal(values.n, 4); H.equal(values[1], result)
            H.equal(values[2], nil); H.equal(values[3], 17); H.equal(values[4], nil)
            H.equal(s.actor.creation, nil)
            H.equal(s.runtime:resolve_template(s.item), nil, "unqualified bare preview has no actor")
            H.equal(_G.Weapons.one_handed_swords_template_1, native)
        end)
        _G.Weapons = prior
        if not ok then error(err, 0) end
    end)
    H.test("645 installed world wrapper admits secondary melee and restores exact context and tuple", function()
        local s, prior_weapons = fixture(), _G.Weapons
        local ok, err = pcall(function()
            local native, custom = s.weapons.one_handed_swords_template_1, s.weapons.cwv_645_elven_sword_style
            local prior_context, result = {}, {}
            _G.Weapons = s.weapons
            s.equipment.slots.slot_melee = nil
            s.owner_missing = true; s.player.player_unit = nil
            s.actor.creation = prior_context
            local calls, hook = 0, world_hook(s)
            local values = pack(hook(function(_, slot, item, _, unit, bot, _, _, _, _, _, career)
                calls = calls + 1
                H.equal(slot, "slot_ranged"); H.equal(item, s.item); H.equal(unit, s.unit)
                H.equal(bot, false); H.equal(career, "es_native")
                H.equal(s.runtime:resolve_template(item), custom)
                return nil, result, nil, 23, nil
            end, {}, "slot_ranged", s.item, {}, s.unit, false, nil, nil, nil, nil, nil, "es_native"))
            H.equal(calls, 1); H.equal(values.n, 5); H.equal(values[1], nil)
            H.equal(values[2], result); H.equal(values[3], nil); H.equal(values[4], 23); H.equal(values[5], nil)
            H.equal(s.actor.creation, prior_context)
            H.equal(_G.Weapons.one_handed_swords_template_1, native)
            H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0)
        end)
        _G.Weapons = prior_weapons
        if not ok then error(err, 0) end
    end)
    H.test("645 installed world wrapper leaves unrelated slots native without swallowing the caller", function()
        local s, prior_weapons = fixture(), _G.Weapons
        local ok, err = pcall(function()
            _G.Weapons = s.weapons
            local hook, calls, prior_context, sentinel = world_hook(s), 0, {}, {}
            s.actor.creation = prior_context
            local values = pack(hook(function()
                calls = calls + 1
                H.equal(s.actor:creation_profile(s.item), nil)
                H.equal(s.runtime:resolve_template(s.item), nil, "unsupported slot retains native fallback")
                return sentinel, nil, false, nil
            end, {}, "slot_hat", s.item, {}, s.unit, false, nil, nil, nil, nil, nil, "es_native"))
            H.equal(calls, 1); H.equal(values.n, 4); H.equal(values[1], sentinel)
            H.equal(values[2], nil); H.equal(values[3], false); H.equal(values[4], nil)
            H.equal(s.actor.creation, prior_context)
            H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0)
        end)
        _G.Weapons = prior_weapons
        if not ok then error(err, 0) end
    end)
    H.test("645 installed creation wrapper restores exact outer context on nested refusal and native errors", function()
        local s, sentinel = fixture(), {}
        local hook = world_hook(s)
        local outer = { item = "unrelated existing outer context" }; s.actor.creation = outer
        local ok, err = pcall(hook, function()
            local live = s.actor.creation
            H.equal(live.item, s.item)
            local inner_item = { name = "we_1h_sword", backend_id = "other" }
            local values = pack(hook(function()
                H.equal(s.actor.creation.item, inner_item)
                H.equal(s.actor:creation_profile(inner_item), nil)
                H.equal(s.actor:creation_profile(s.item), nil)
                return nil, "native falsey tuple", nil
            end, {}, "slot_melee", inner_item, {}, s.unit, false, nil, nil, nil, nil, nil, "other"))
            H.equal(values.n, 3); H.equal(values[2], "native falsey tuple")
            H.equal(s.actor.creation, live)
            error(sentinel, 0)
        end, {}, "slot_melee", s.item, {}, s.unit, false, nil, nil, nil, nil, nil, "es_native")
        H.equal(ok, false); H.equal(err, sentinel); H.equal(s.actor.creation, outer)
    end)
    H.test("645 initial creation rejects contradictory owner and career facts without repairing them", function()
        local s = fixture()
        local hook, calls = world_hook(s), 0
        s.player_manager_methods.owner = function() return s.remote_player end
        local result = hook(function()
            calls = calls + 1
            H.equal(s.actor:creation_profile(s.item), nil)
            return nil, "native"
        end, {}, "slot_melee", s.item, {}, s.unit, false, nil, nil, nil, nil, nil, "es_native")
        H.equal(result, nil); H.equal(calls, 1); H.equal(s.actor.creation, nil)
        H.equal(s.inventory.player, s.player); H.equal(s.inventory._career_name, "es_native")
        H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0)
    end)
    H.test("645 unknown remote actor does not burn token and identical later input is admissible", function()
        local s = fixture()
        s.remote_pi = nil
        H.equal(s.runtime:accept_style_edge("remote", "slot_melee", s.family, "elven", "style_channel"), false)
        H.equal(s.runtime.remote.remote, nil); H.equal(next(s.runtime.pending_remote), nil)
        H.equal(next(s.runtime.fallback_remote), nil); H.equal(s.coalescer.depth(), 0)
        s.remote_pi = 7
        local changed, token = s.runtime:accept_style_edge("remote", "slot_melee", s.family, "elven", "style_channel")
        H.equal(changed, true); H.equal(token, s.family .. ":elven")
        H.equal(s.runtime.remote.remote.slot_melee.token, token)
        H.equal(s.runtime.store.items.sword_id, "elven")
    end)
    H.test("645 actual queued Sword rebuild refuses changed actor at coalescer drain", function()
        local s = fixture()
        H.equal(s.runtime:accept_style_edge("remote", "slot_melee", s.family, "elven", "identity"), true)
        H.equal(s.coalescer.depth(), 1)
        local token = s.runtime.remote.remote.slot_melee.token
        s.remote_pi = 12
        s.coalescer.drain({ unit_api = s.units, script_unit = s.script, silent = true })
        H.equal(s.wields, 0); H.equal(s.coalescer.depth(), 0)
        H.equal(s.runtime.remote.remote.slot_melee.token, token, "accepted preference remains dormant")
        H.equal(s.runtime.store.items.sword_id, "elven")
    end)
    H.test("645 actual queued Sword rebuild executes once while the same actor stays admitted", function()
        local s = fixture()
        H.equal(s.runtime:accept_style_edge("remote", "slot_melee", s.family, "elven", "identity"), true)
        H.equal(s.coalescer.depth(), 1)
        s.coalescer.drain({ unit_api = s.units, script_unit = s.script, silent = true })
        H.equal(s.wields, 1); H.equal(s.coalescer.depth(), 0)
    end)
    H.test("645 remote effective template and husk selection recheck actor without erasing edge", function()
        local s, prior = fixture(), _G.Weapons
        local ok, err = pcall(function()
            local custom = s.weapons.cwv_645_elven_sword_style; _G.Weapons = s.weapons
            s.runtime:accept_style_edge("remote", "slot_melee", s.family, "elven", "style_channel")
            H.equal(s.runtime:effective_template_name(s.remote_item, nil, s.remote_unit, "slot_melee"), "cwv_645_elven_sword_style")
            H.equal(s.runtime:begin_husk_wield({ _unit = s.remote_unit }, "slot_melee"), true)
            H.equal(s.runtime:resolve_template(s.remote_item), custom)
            s.remote_pi = 12
            H.equal(s.runtime:resolve_template(s.remote_item), nil)
            H.equal(s.runtime:effective_template_name(s.remote_item, nil, s.remote_unit, "slot_melee"), nil)
            H.truthy(s.runtime.remote.remote.slot_melee)
            s.runtime:end_husk_wield()
        end)
        _G.Weapons = prior
        if not ok then error(err, 0) end
    end)
    H.test("645 non-Sword runtime and queue keep their pre-existing admission behavior", function()
        local s = fixture()
        local item = { name = "es_2h_sword", backend_id = "non_sword" }
        H.truthy(s.runtime:describe(item))
        H.equal(s.runtime:actor_admitted("es_2h_sword", nil, nil, function() error("must not resolve") end), true)
        local calls = 0
        s.coalescer.request(s.remote_unit, "ordinary", function() calls = calls + 1 end)
        s.coalescer.drain({ unit_api = s.units, script_unit = s.script, silent = true })
        H.equal(calls, 1)
    end)
    H.test("645 installed desktop UI passes selected actor through its real async caller", function()
        local definitions = { scenegraph_definition = {}, widgets = {} }
        local env = setmetatable({ printf = function() end,
            local_require = function(name)
                if name:find("hero_window_loadout_definitions", 1, true) then return definitions end
                error("console intentionally absent from this desktop caller test")
            end }, { __index = _G })
        local s, hooks = fixture(env), {}
        s.local_pi = 12
        s.mod.hook = function(_, class, method, callback) hooks[class .. "." .. method] = callback end
        H.equal(s.policy.install_loadout_ui(s.mod, s.runtime, s.ui_installer), true)
        local window = { hero_name = "empire_soldier", career_index = 1,
            parent = { get_selected_loadout_slot_index = function() return 1 end },
            _equipment_items = { { data = s.item, backend_id = "sword_id" } },
            _widgets_by_name = {
                cwv_combat_style_button = { content = { button_hotspot = {} } },
                cwv_combat_style_status = { content = {} },
            } }
        local populate = assert(hooks["HeroWindowLoadout._populate_loadout"])
        H.equal(populate(function() return 17 end, window), 17)
        local content = window._widgets_by_name.cwv_combat_style_button.content
        H.equal(content.visible, true, "selected Empire, not viewer Elf")
        window.hero_name = "wood_elf"; populate(function() end, window)
        H.equal(content.visible, false)
        window.hero_name = "empire_soldier"; populate(function() end, window)
        content.button_hotspot.on_release = true
        local values = pack(assert(hooks["HeroWindowLoadout._handle_input"])(function() return "native", nil, 3, nil end, window))
        H.equal(values.n, 4); H.equal(values[1], "native"); H.equal(values[3], 3)
        H.equal(type(s.complete), "function", "actual UI request reached real acquisition seam")
        window.hero_name = "wood_elf"; s.complete(true)
        H.equal(s.writes, 0); H.equal(s.runtime.store.items.sword_id, "elven")
    end)
    H.test("645 installed console callbacks use selected actor and reject changed async selection", function()
        local console = { generic_input_actions = { default = {}, default_no_customization = {} } }
        console.create_loadout_grid_func = function()
            return { element = { passes = {} }, content = { rows = 1, columns = 1,
                profile_index = 19, career_index = 1, hotspot_1_1 = { is_selected = true } },
                style = { customize_hotspot_1_1 = { offset = { 20, 3, 2 } },
                    customize_item_hover_1_1 = { offset = { 20, 3, 2 } } } }
        end
        local env = setmetatable({ printf = function() end,
            local_require = function(name)
                if name:find("hero_window_loadout_console_definitions", 1, true) then return console end
                error("desktop intentionally absent from this console caller test")
            end }, { __index = _G })
        local s, hooks = fixture(env), {}
        s.local_pi = 12
        s.mod.hook = function(_, class, name, callback) hooks[class .. "." .. name] = callback end
        H.equal(s.policy.install_loadout_ui(s.mod, s.runtime, s.ui_installer), true)
        local grid = console.create_loadout_grid_func()
        H.equal(grid.cwv_combat_style_decorated, true)
        grid.content.item_1_1 = { data = s.item, backend_id = "sword_id" }
        local window = { hero_name = "empire_soldier", career_index = 1,
            _widgets_by_name = { loadout_grid = grid },
            _input_service = function() return { get = function(_, name) return name == "special_1" end } end }
        local populate = assert(hooks["HeroWindowLoadoutConsole._populate_loadout"])
        H.equal(populate(function() return 29 end, window), 29)
        H.equal(grid.content.cwv_style_hotspot_1_1.cwv_visible, true,
            "actual window actor, not viewer or stale grid indices")
        local native_calls = 0
        local input = assert(hooks["HeroWindowLoadoutConsole._handle_gamepad_input"])
        input(function() native_calls = native_calls + 1 end, window)
        H.equal(native_calls, 0); H.equal(type(s.complete), "function")
        window.hero_name = "wood_elf"; s.complete(true)
        H.equal(s.writes, 0); H.equal(s.runtime.store.items.sword_id, "elven")
        input(function() native_calls = native_calls + 1 end, window)
        H.equal(native_calls, 1); H.equal(grid.content.cwv_style_hotspot_1_1.cwv_visible, false)
        H.equal(s.wields, 0)
    end)
    H.test("645 installed identity owner refuses unknown actor before lifecycle cache and recovers same payload", function()
        local s = fixture()
        local Appearance = load("_cwv_combat_style_appearance")
        H.equal(Appearance.SUPPORTED_FAMILIES[s.family], true, "real immutable appearance admission")
        local om = { combat_styles = s.runtime, combat_style_policy = s.policy,
            combat_style_appearance = Appearance, exact_appearance = load("_cwv_exact_appearance"),
            appearance_descriptor = dofile(root .. "/tools/shared_lib/_lib_appearance_descriptor.lua"),
            appearance_lifecycle_policy = load("_cwv_appearance_lifecycle"),
            identity_peer_pull = load("_cwv_identity_peer_pull"), identity_peer_cleanup = load("_cwv_identity_peer_cleanup"),
            peer_resolver = load("_cwv_peer_resolver"), exact_wire_runtime = { install_damage = function() end },
            _skin_keys = {}, cosmetic_skin_wire = { is_cwv_skin = function() return false end },
            _cwv_key_for_item = function() return nil end }
        local env = setmetatable({ printf = function() end, get_mod = function() end,
            ItemMasterList = { es_1h_sword = { item_type = "es_1h_sword", right_hand_unit = "units/native_sword" } },
            WeaponSkins = { skins = {} }, Managers = s.managers,
            LoadoutUtils = false, CosmeticUtils = false, PlayerManager = false, NetworkLookup = {},
        }, { __index = _G })
        local sent = 0
        local mod = { _cwv_rewield = s.coalescer, hook = function() end, network_register = function() end,
            network_send = function() sent = sent + 1; return true end,
            dofile = function(_, name)
                if name:find("_cwv_outrider_projectile_wire", 1, true) then return { install = function() end } end
                if name:find("_lib_network_lookup", 1, true) then return {} end
                if name:find("_cwv_identity_descriptor_planner", 1, true) then return load("_cwv_identity_descriptor_planner", env) end
                error("unexpected module " .. name)
            end }
        load("_cwv_item_identity_transport_owner", env)(mod, { om = om, find_def = function() return nil end, custom_skin_keys = {} })
        local payload = assert(om._cwv_identity_payloads({ slot_melee = { item_data = s.item } })[1])
        H.equal(payload.provider, Appearance.PROVIDER)
        local custom_node = s.weapons.cwv_645_elven_sword_style.actions.action_one.default
        local prior_event = custom_node.anim_event_3p
        local native_world = om.exact_appearance.resolve_spawn_descriptor
        om.exact_appearance.resolve_spawn_descriptor = function(...)
            local result = pack(native_world(...))
            custom_node.anim_event_3p = "foreign-during-native-world-read"
            return unpack(result, 1, result.n)
        end
        local declined = assert(om._cwv_identity_payloads({ slot_melee = { item_data = s.item } })[1])
        H.equal(declined.provider, "", "actual immutable builder rechecks C after native world read")
        H.equal(om._cwv_local_style_descriptor("sword_id"), nil)
        H.equal(s.runtime.store.items.sword_id, "elven")
        om.exact_appearance.resolve_spawn_descriptor = native_world
        custom_node.anim_event_3p = prior_event
        payload = assert(om._cwv_identity_payloads({ slot_melee = { item_data = s.item } })[1])
        H.equal(payload.provider, Appearance.PROVIDER)
        local before = next(om._appearance_lifecycle._remote)
        local schema = om.appearance_lifecycle_policy.SCHEMA
        for _, method in ipairs({ "remote_actor_admitted", "package", "descriptor_actor_admitted" }) do
            local original = s.runtime[method]
            s.runtime[method] = nil
            local ok, accepted, result = pcall(om._cwv_accept_identity, "remote", schema, payload)
            s.runtime[method] = original
            H.equal(ok, true, "missing Sword runtime method refuses instead of raising")
            H.equal(accepted, false); H.equal(result, nil)
            H.equal(next(om._appearance_lifecycle._remote), before,
                "missing Sword authority never burns the remote edge")
        end
        s.remote_pi = nil
        local changed, descriptor, reason = om._cwv_accept_identity("remote", schema, payload)
        H.equal(changed, false); H.equal(descriptor, nil)
        H.equal(next(om._appearance_lifecycle._remote), before, "no negative cache/token burn before admission")
        s.remote_pi = 7
        custom_node.anim_event_3p = "foreign"
        changed, descriptor, reason = om._cwv_accept_identity("remote", schema, payload)
        H.equal(changed, false); H.equal(descriptor, nil)
        H.equal(next(om._appearance_lifecycle._remote), before, "no cache/token burn before retained construction")
        custom_node.anim_event_3p = prior_event
        changed, descriptor, reason = om._cwv_accept_identity("remote", schema, payload)
        H.equal(changed, true); H.truthy(descriptor); H.equal(reason, "exact")
        H.equal(om._cwv_identity_descriptor_for_peer("remote", "slot_melee", "es_1h_sword"), descriptor)
        s.remote_pi = 12
        H.equal(om._cwv_identity_descriptor_for_peer("remote", "slot_melee", "es_1h_sword"), nil)
        s.remote_pi = 7
        H.equal(om._cwv_identity_descriptor_for_peer("remote", "slot_melee", "es_1h_sword"), descriptor)
        H.equal(om._appearance_lifecycle:track_delivery("receiver", { slot_melee = { item_data = s.item } }, "actor-test"), 1)
        local before_send = sent
        custom_node.anim_event_3p = "foreign"
        H.equal(om._cwv_identity_descriptor_for_peer("remote", "slot_melee", "es_1h_sword"), nil)
        H.equal(om._cwv_local_style_descriptor("sword_id"), nil)
        om._appearance_lifecycle:step_deliveries(1)
        H.equal(sent, before_send, "cached retry cannot emit after retained construction loss")
        H.equal(s.runtime.store.items.sword_id, "elven")
        custom_node.anim_event_3p = prior_event
        H.equal(om._cwv_identity_descriptor_for_peer("remote", "slot_melee", "es_1h_sword"), descriptor)
        s.local_pi = 12
        om._appearance_lifecycle:step_deliveries(1)
        H.equal(sent, before_send, "cached Sword retry cannot emit after actor changed")
        H.equal(s.runtime.store.items.sword_id, "elven")
    end)
    return { fixture = fixture, world_hook = world_hook, load = load }
end
