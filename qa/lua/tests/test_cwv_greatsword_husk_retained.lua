-- #660 narrow remote post-wield contract. This drives the actual planner,
-- fingerprinted payload receiver, spawn adapter, coalescer, retained owner and
-- shared atomic writer. Engine unit state is a private numerical ledger; this
-- is not native rendering, animation-frame retention or multiplayer proof.
return function(H, repo_root)
    local root = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local function clone(value)
        if type(value) ~= "table" then return value end
        local copy = {}; for key, child in pairs(value) do copy[key] = clone(child) end
        return copy
    end
    local function fixture(opts)
        opts = opts or {}
        local env = setmetatable({}, { __index = _G }); env._G = env
        local function load(name)
            local chunk = assert(loadfile(root .. name .. ".lua")); setfenv(chunk, env); return chunk()
        end
        local D, A = load("_lib_appearance_descriptor"), load("_cwv_combat_style_appearance")
        local Policy, Planner = load("_cwv_combat_styles"), load("_cwv_identity_descriptor_planner")
        local Life, Rewield = load("_cwv_appearance_lifecycle"), load("_cwv_style_rewield")
        local Coalescer, Exact = load("_cwv_rewield_coalescer"), load("_cwv_exact_appearance")
        local reconcile_axes = {}
        local new_reconciler = D.new_reconciler
        D.new_reconciler = function(options)
            local reconciler = new_reconciler(options)
            local reconcile = reconciler.reconcile
            reconciler.reconcile = function(descriptor, surface, edge, target, context)
                reconcile_axes[#reconcile_axes + 1] = { surface = surface, edge = edge }
                return reconcile(descriptor, surface, edge, target, context)
            end
            return reconciler
        end
        local writes, logs, checks = {}, {}, {}
        local owner = { alive = true }
        local unit_api = {
            alive = function(u)
                if opts.throw_owner and u == owner then error("owner read") end
                if opts.unknown_owner and u == owner then return nil end
                return type(u) == "table" and u.alive == true
            end,
            has_node = function(u, n) return u.alive == true and n == 0 end,
            local_position = function(u, n) assert(n == 0); if opts.throw_read then error("read") end; return clone(u.position) end,
            local_scale = function(u, n) assert(n == 0); return clone(u.scale) end,
            local_rotation = function(u, n) assert(n == 0); return clone(u.rotation) end,
            set_local_pose = function(u, n, pose)
                assert(n == 0); writes[#writes + 1] = clone(pose)
                if opts.discard_write then return end
                u.position, u.scale, u.rotation = clone(pose.position), clone(pose.scale), clone(pose.rotation)
                if opts.after_write then opts.after_write() end
            end,
        }
        local vector = setmetatable({ to_elements = function(v) return unpack(v) end },
            { __call = function(_, x, y, z) return { x, y, z } end })
        local quaternion = { to_elements = function(q) return unpack(q) end,
            from_elements = function(x, y, z, w) return { x, y, z, w } end,
            from_euler_angles_xyz = function(x, y, z)
                assert(x == 0 and y == 0 and z == 0, "fixture admits identity Euler only")
                return { 0, 0, 0, 1 }
            end }
        local matrix = { from_quaternion_position_scale = function(r, p, s)
            return { rotation = clone(r), position = clone(p), scale = clone(s) }
        end }
        local WA = load("_lib_weapon_appearance").new({ unit = unit_api, vector_new = vector,
            vector_to_elements = vector.to_elements, quaternion = quaternion, matrix4x4 = matrix })
        env.Unit, env.Vector3, env.Quaternion = unit_api, vector, quaternion
        env.printf = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end
        env.ScriptUnit = { extension = function() error("unexpected extension") end }
        env.Managers = { package = { has_loaded = function() return true end },
            player = { player_from_peer_id = function() return { player_unit = owner } end } }
        env.NetworkLookup, env.ItemMasterList, env.WeaponSkins = { anims = {} }, {}, { skins = {} }
        local item_key, style = "es_2h_sword", opts.control and "greatsword" or "bretonnian"
        local item = { name = item_key, backend_id = "exact-greatsword-instance" }
        local native_unit = "units/weapons/player/wpn_empire_2h_sword_01_t1/wpn_empire_2h_sword_01_t1"
        local items = { [item_key] = { key = item_key, right_hand_unit = native_unit } }
        local presentation = { right_hand_scale_3p = { 0.8, 0.9, 1.1 },
            right_hand_offset_3p = { 0.1, -0.2, 0.3 } }
        local om = { appearance_descriptor = D, combat_style_appearance = A,
            combat_style_policy = Policy, exact_appearance = Exact,
            _cwv_key_for_item = function() return nil end }
        om.combat_styles = {
            describe = function(_, value)
                return { item_key = value.name, identity = value.backend_id,
                    family_id = "greatsword", style_id = style, package = Policy.package(value.name, style) }
            end,
            presentation = function(_, key)
                if key == "greatsword_bretonnian" then return presentation end
            end,
            member_key = function(_, value) return value.name end,
            effective_template_name = function() return Policy.package(item_key, style).template end,
        }
        om.peer_resolver = { peer_player = function() return { player_unit = owner }, "fixture" end }
        local planner = Planner.new({ om = om, retained = {}, find_def = function() end,
            get_item_master = function() return items end, get_weapon_skins = function() return {} end,
            printf = env.printf })
        local life = Life.new({ resolve_local = planner.resolve_local, resolve_remote = planner.resolve_remote })
        local payload = assert(life:payload_for("slot_melee", { item_data = item }))
        local _, descriptor, reason = life:accept("sender", Life.SCHEMA, payload)
        assert(descriptor and reason == "exact", reason)
        local current, state = descriptor, "exact"
        om._husk_identity_descriptor = function() return current, state end
        om.style_rewield, om.weapon_appearance = Rewield, WA
        env._om = om
        env._rt_register = function(name, fn) checks[name] = fn end
        local file = assert(io.open(root .. "character_weapon_variants.lua", "rb"))
        local entry = file:read("*a"):gsub("\r\n", "\n"); file:close()
        env.policy, env.mod, env.style_resource_resident = Policy, { _cwv_rewield = Coalescer }, function() return true end
        local first = assert(entry:find("\tlocal _style_rewield_deps =", 1, true))
        local finish = assert(entry:find("\n\n\t_om.combat_styles = policy.install", first, true))
        local install = assert(loadstring(entry:sub(first, finish - 1) .. "\nreturn _style_rewield_deps",
            "=actual-entry-Greatsword-retained-context"))
        setfenv(install, env)
        local deps = install()
        local retained = assert(om._greatsword_husk_retained)
        assert(deps.retained_reconcile == retained.reconcile)
        local apply_initial
        if opts.initial_writer then
            local function source(name)
                local file = assert(io.open(root .. name .. ".lua", "rb"))
                local value = file:read("*a"):gsub("\r\n", "\n"); file:close(); return value
            end
            local function between(value, begin, ending)
                local a = assert(value:find(begin, 1, true)); local b = assert(value:find(ending, a, true))
                return value:sub(a, b - 1)
            end
            local producer = source("_cwv_weapon_transform_owner")
            local block = between(producer, "local function _resolve_field", "\nlocal _transform_map")
                .. between(producer, "local function _transform_unit", "\n-- #604 single transform-scheduling")
                .. between(producer, "local function _plan_cwv_hand_transform", "\n-- Vanilla mace+sword")
                .. "\nreturn _plan_cwv_hand_transform, _apply_cwv_hand_transform"
            local producer_env = setmetatable({ WA = WA, _type_transforms = {} }, { __index = env })
            local chunk = assert(loadstring(block, "=actual-transform-owner-functions")); setfenv(chunk, producer_env)
            local plan; plan, apply_initial = chunk()
            local bound = load("_cwv_husk_transform_policy").bind({ find_def = function() return nil end,
                resolve_def = function() return nil end, plan_transform = plan, model_by_unit = {}, hand_unit = A.hand_unit })
            om._cwv_select_husk_transform_def, om._cwv_husk_transform_apply_plan = bound.select, bound.plan
            local policy_source = source("_cwv_combat_styles")
            local remote_env = setmetatable({ runtime = {},
                deps = { peer_for_owner = function() return "sender" end, style_descriptor_transform = A.transform_decision },
                remote = { sender = { slot_melee = { descriptor = descriptor } } } }, { __index = env })
            local remote_chunk = assert(loadstring(between(policy_source, "\tfunction runtime:remote_transform", "\n\tlocal function persist")
                .. "\nreturn runtime.remote_transform", "=actual-style-remote-transform"))
            setfenv(remote_chunk, remote_env)
            om.combat_styles.remote_transform = remote_chunk()
        end
        load("_cwv_husk_path")(nil, { om = om, variant_definitions = {}, find_def = function() end,
            is_unit = unit_api.alive, apply_cwv_hand_transform = apply_initial or function() error("isolated legacy writer") end,
            triplet_text = function() return "unused" end })
        -- Controlled isolated cases deliberately disconnect the legacy sibling;
        -- the composition oracle and native control enable its actual source.
        om._husk_strip_cwv_ammo, om._probe_579_hand_compare, om._husk_postcondition_log = nil, nil, nil
        if not opts.initial_writer then om._husk_apply_cwv_transform = nil end
        local equipment = { slots = { slot_melee = { item_data = item } }, wielded_slot = "slot_melee" }
        local inventory = { _equipment = equipment, wielded_slot = "slot_melee" }
        local last_unit
        local function spawn()
            local u = { alive = true, position = { 0.4, 0.5, 0.6 }, scale = { 1, 1, 1 }, rotation = { 0, 0, 0, 1 } }
            if opts.zero_quaternion then u.rotation = { 0, 0, 0, 0 } end
            om._husk_adapter_post("right", item, { right_hand_unit = native_unit }, "slot_melee", owner, u)
            last_unit = u; equipment.right_hand_wielded_unit_3p = u
            return u
        end
        inventory.wield = function() spawn(); if opts.after_spawn then opts.after_spawn(last_unit) end end
        env.ScriptUnit.extension, env.ScriptUnit.has_extension = function() return inventory end, function() return inventory end
        local script_unit = env.ScriptUnit
        local f = { D = D, A = A, payload = payload, descriptor = descriptor, life = life,
            reconcile_axes = reconcile_axes,
            om = om, owner = owner, retained = retained, checks = checks, logs = logs, writes = writes,
            equipment = equipment, inventory = inventory, spawn = spawn, options = opts }
        function f.set_current(value, why) current, state = value, why or "exact" end
        function f.unit() return last_unit end
        function f.queue()
            local verdict, detail
            local queued, why = Rewield.queue_rebuild(deps, "sender", "slot_melee", "greatsword", style,
                function(v, d) verdict, detail = v, d end, descriptor)
            assert(queued, "actual queue rejected: " .. tostring(why))
            assert(verdict == nil, "no synchronous verdict")
            Coalescer.drain({ silent = true, unit_api = unit_api, script_unit = script_unit })
            return verdict, detail
        end
        return f
    end
    H.test("#660 actual planner receiver queued callback repairs Greatsword pose", function()
        local f = fixture()
        H.equal(f.descriptor.generation, 0, "wire semantic generation remains unchanged")
        H.equal(f.payload.fingerprint, f.descriptor.fingerprint)
        local status = f.queue(); H.equal(status, "ok")
        H.deep_equal(f.reconcile_axes, { { surface = "husk", edge = "equip" } },
            "post-wield uses the existing canonical equipment lifecycle axis")
        H.equal(string.format("%.5f,%.5f,%.5f", unpack(f.unit().position)), "0.50000,0.30000,0.90000")
        H.deep_equal(f.unit().scale, { 0.8, 0.9, 1.1 })
        H.equal(#f.writes, 1)
        H.equal(f.checks.issue660_greatsword_husk_retained(), nil)
        H.truthy(f.logs[#f.logs]:find("semantic_generation=0", 1, true))
        H.truthy(f.logs[#f.logs]:find("actual_position=[0.50000,0.30000,0.90000]", 1, true))
    end)
    H.test("#660 unmodified Greatsword control is observed without pose writes", function()
        local f = fixture({ control = true, initial_writer = true, after_spawn = function(u) u.position = { 7, 8, 9 } end })
        H.equal(f.queue(), "ok")
        H.equal(#f.writes, 0); H.deep_equal(f.unit().position, { 7, 8, 9 })
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("^skip:"))
    end)
    H.test("#660 setter success with rejected retained pose cannot pass", function()
        local f = fixture({ discard_write = true })
        H.equal(f.queue(), "partial"); H.equal(#f.writes, 1)
        H.truthy(f.checks.issue660_greatsword_husk_retained() ~= nil)
    end)
    H.test("#660 unreadable native baseline fails without writes", function()
        local f = fixture({ throw_read = true }); H.equal(f.queue(), "partial"); H.equal(#f.writes, 0)
        H.truthy(not f.checks.issue660_greatsword_husk_retained():find("^skip:"), "an active capture failure is not out of scope")
    end)
    H.test("#660 stale source identity fails without repairing foreign state", function()
        local f = fixture({ after_spawn = function(u) u.position = { 7, 8, 9 } end })
        f.set_current(nil, "unavailable"); H.equal(f.queue(), "partial"); H.equal(#f.writes, 0)
    end)
    H.test("#660 private observation generations reject superseded render units", function()
        local f = fixture(); local old = f.spawn(); local fresh = f.spawn()
        f.equipment.right_hand_wielded_unit_3p = old
        local ok, why = f.retained.reconcile(f.descriptor, f.owner, f.inventory, "slot_melee")
        H.equal(ok, false); H.equal(why, "spawn-generation-stale"); H.equal(#f.writes, 0)
        f.equipment.right_hand_wielded_unit_3p = fresh
        H.equal(f.retained.reconcile(f.descriptor, f.owner, f.inventory, "slot_melee"), true)
    end)
    H.test("#660 missing and foreign spawn generations never manufacture evidence", function()
        local f = fixture(); f.equipment.right_hand_wielded_unit_3p = { alive = true }
        H.equal(f.retained.reconcile(f.descriptor, f.owner, f.inventory, "slot_melee"), false)
        f.spawn(); H.equal(f.retained.reconcile(f.descriptor, { alive = true }, f.inventory, "slot_melee"), false)
        H.equal(#f.writes, 0)
    end)
    H.test("#660 each bounded post-wield revisit reobserves actual drift", function()
        local f = fixture(); H.equal(f.queue(), "ok")
        f.unit().position = { 0, 0, 0 }
        H.equal(f.retained.reconcile(f.descriptor, f.owner, f.inventory, "slot_melee"), true)
        H.equal(string.format("%.5f,%.5f,%.5f", unpack(f.unit().position)), "0.50000,0.30000,0.90000"); H.equal(#f.writes, 2)
    end)
    H.test("#660 named check rejects replaced target and never trusts historic PASS", function()
        local f = fixture(); H.equal(f.queue(), "ok")
        f.equipment.right_hand_wielded_unit_3p = { alive = true }
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("render%-target%-replaced"))
    end)
    H.test("#660 Lua 5.1 weak ledgers release superseded render handles", function()
        local f = fixture(); local old = f.spawn()
        local witness = setmetatable({ old }, { __mode = "v" })
        f.spawn(); old = nil; collectgarbage("collect"); collectgarbage("collect")
        H.equal(witness[1], nil, "a weak-key ledger must not retain its key through the value")
    end)
    H.test("#660 foreign immutable generation cannot borrow a captured baseline", function()
        local f = fixture(); f.spawn()
        local data = f.D.raw(f.descriptor); data.generation = 123
        local foreign = assert(f.D.build(data))
        local ok, why = f.retained.reconcile(foreign, f.owner, f.inventory, "slot_melee")
        H.equal(ok, false); H.equal(why, "descriptor-foreign"); H.equal(#f.writes, 0)
    end)
    H.test("#660 post-capture read errors and dead units cannot pass", function()
        local f = fixture(); f.spawn(); f.options.throw_read = true
        H.equal(f.retained.reconcile(f.descriptor, f.owner, f.inventory, "slot_melee"), false)
        f.unit().alive = false
        H.equal(f.retained.reconcile(f.descriptor, f.owner, f.inventory, "slot_melee"), false)
        local dead_owner = fixture(); dead_owner.spawn(); dead_owner.owner.alive = false
        H.equal(dead_owner.retained.reconcile(dead_owner.descriptor, dead_owner.owner, dead_owner.inventory, "slot_melee"), false)
        H.equal(#dead_owner.writes, 0)
    end)
    H.test("#660 source identity lost during atomic write cannot commit a verdict", function()
        local f = fixture()
        f.options.after_write = function() f.set_current(nil, "unavailable") end
        H.equal(f.queue(), "partial")
        H.truthy(f.checks.issue660_greatsword_husk_retained() ~= nil)
    end)
    H.test("#660 invalid finite quaternion baseline is refused before pose write", function()
        local f = fixture({ zero_quaternion = true })
        H.equal(f.queue(), "partial"); H.equal(#f.writes, 0)
    end)
    H.test("#660 production initial-transform and queued retained adapters compose without double offset", function()
        local initial
        local f = fixture({ initial_writer = true, after_spawn = function(u)
            initial = clone(u.position); u.position = { 7, 8, 9 }
        end })
        H.equal(f.queue(), "ok")
        H.equal(string.format("%.5f,%.5f,%.5f", unpack(initial)), "0.50000,0.30000,0.90000",
            "actual initial writer must run after baseline capture")
        H.deep_equal(f.unit().position, initial, "retained repair must not add the offset twice")
        H.equal(#f.writes, 2); H.equal(f.checks.issue660_greatsword_husk_retained(), nil)
    end)
    H.test("#660 named check skips positive owner and weapon deactivation only", function()
        local f = fixture(); H.equal(f.queue(), "ok")
        f.inventory.wielded_slot = "slot_ranged"
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("^skip:"))
        f.inventory.wielded_slot = "slot_melee"
        f.equipment.slots.slot_melee.item_data = { name = "es_1h_sword" }
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("^skip:"))
        f.equipment.slots.slot_melee.item_data = { name = "es_2h_sword" }
        f.set_current(nil, "native")
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("^skip:"))
        local native = fixture({ control = true })
        f.set_current(assert(f.D.build(native.D.raw(native.descriptor))))
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("^skip:"))
        f.owner.alive = false
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("^skip:"))
    end)
    H.test("#660 named check never skips active identity and readback defects", function()
        local f = fixture(); H.equal(f.queue(), "ok")
        for _, state in ipairs({ "none", "unavailable", "stale_base" }) do
            f.set_current(nil, state)
            local result = f.checks.issue660_greatsword_husk_retained()
            H.truthy(result and not result:find("^skip:"), "active authority loss must fail: " .. state)
        end
        local data = f.D.raw(f.descriptor); data.transform_3p = nil
        f.set_current(assert(f.D.build(data)))
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("authored transform is missing"))
        data.base_item_key, data.style_id, data.effective_template = "wh_2h_sword", "greatsword", "two_handed_swords_template_1"
        f.set_current(assert(f.D.build(data)))
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("base is foreign"))
        f.set_current(f.descriptor); f.options.throw_read = true
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("not retained"))
        f.options.throw_read = false; f.equipment.slots.slot_melee.item_data = nil
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("item unreadable"))
        f.options.throw_owner = true
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("liveness unreadable"))
        f.options.throw_owner, f.options.unknown_owner = false, true
        H.truthy(f.checks.issue660_greatsword_husk_retained():find("liveness unreadable"))
    end)
end
