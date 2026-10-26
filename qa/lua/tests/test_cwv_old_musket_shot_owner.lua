-- #428: exact local owner transaction/admission/latched-shot contracts.
-- Private environments retain raw global/table/metatable shape on every path.
return function(H, root)
    local prefix = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local Snapshot = dofile(root .. "/qa/lua/fixtures/wt_authentic_pistol_native_6_13.lua")
    local KEY, NATIVE = "cwv_old_musket_shot", "shot_sniper"
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close()
        s = s:gsub("\r\n", "\n")
        if s:sub(1, 3) == string.char(239, 187, 191) then s = s:sub(4) end
        return s
    end
    local function run(source, env, name)
        local chunk = assert(loadstring(source, "@" .. (name or "issue428-private")))
        setfenv(chunk, env); return chunk()
    end
    local function shape(t)
        local result = { target = t, meta = getmetatable(t), cells = {} }
        for k, v in next, t do result.cells[k] = v end
        return result
    end
    local function unchanged(row)
        H.equal(getmetatable(row.target), row.meta, "exact metatable")
        local function same(a, b, message)
            if type(a) == "number" and a ~= a then H.truthy(type(b) == "number" and b ~= b, message)
            else H.equal(a, b, message) end
        end
        for k, v in next, row.cells do same(rawget(row.target, k), v, "raw prior field") end
        for k, v in next, row.target do same(rawget(row.cells, k), v, "raw introduced field") end
    end
    local function context(config)
        config = config or {}
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.table = setmetatable({}, { __index = table })
        env.DamageProfileTemplates = {}; env.Weapons = {}
        run(Snapshot.is_class_instance, env); run(Snapshot.clone, env); run(Snapshot.donor, env)
        local state = { _cwv_damage_profile_wire_source = {}, _cwv_damage_profile_generation = 0 }
        local lookup = { [1] = NATIVE, [NATIVE] = 1 }
        local logs = {}
        local helper = assert(loadfile(root .. "/tools/shared_lib/_lib_network_lookup.lua"))()
        local opts = { state = state, lookup_helper = helper,
            profiles = function() return env.DamageProfileTemplates end,
            lookup = function() return lookup end, weapons = function() return env.Weapons end,
            clone = function(value) return env.table.clone(value, true) end,
            emit = function(...) logs[#logs + 1] = { ... } end }
        if config.adjust then config.adjust(opts, env, lookup, state) end
        local owner = run(read(prefix .. "_cwv_old_musket_shot_owner.lua"), env).new(opts)
        local c = { env = env, state = state, lookup = lookup, owner = owner, opts = opts, logs = logs }
        function c.publish()
            local key = owner.prepare(); if not key then return nil end
            local action = { damage_profile = key, total_time = 0.5 }
            local template = { actions = { action_one = { default = action } } }
            H.truthy(owner.publish_template(env.Weapons, template,
                { { action = action, group = "action_one", name = "default" } }))
            c.action, c.template = action, template
            return action
        end
        return c
    end
    local function raw_state(c)
        return { shape(c.env.DamageProfileTemplates), shape(c.lookup), shape(c.state),
            shape(c.state._cwv_damage_profile_wire_source) }
    end
    local function all_unchanged(rows) for _, row in ipairs(rows) do unchanged(row) end end

    H.test("#428 composite publication preserves donor math pair generation and idempotence", function()
        local c = context(); local donor = c.env.table.clone(c.env.DamageProfileTemplates[NATIVE], true)
        H.equal(c.owner.prepare(), KEY)
        local p = c.env.DamageProfileTemplates[KEY]
        H.equal(c.lookup[2], KEY); H.equal(c.lookup[KEY], 2)
        H.equal(c.state._cwv_damage_profile_wire_source[KEY], NATIVE)
        H.equal(c.state._cwv_damage_profile_generation, 1); H.equal(c.state._cwv_wire_fallback_profile_id, 1)
        H.equal(p.default_target.power_distribution_near.attack, donor.default_target.power_distribution_near.attack * 1.5)
        H.equal(p.default_target.power_distribution_far.impact, donor.default_target.power_distribution_far.impact * 1.5)
        H.equal(p.cleave_distribution.attack, 1.5); H.equal(p.cleave_distribution.impact, 0.6)
        for i = 1, 6 do H.equal(p.armor_modifier_near.attack[i], donor.armor_modifier_near.attack[i] + (i >= 4 and 0.2 or 0)) end
        H.deep_equal(c.env.DamageProfileTemplates[NATIVE], donor, "native donor unchanged")
        local before = raw_state(c); H.equal(c.owner.prepare(), KEY); all_unchanged(before)
        c.publish(); H.truthy(c.owner.admit({ item_key = "cwv_es_musket_old", template = "old_musket_template" })); H.equal(c.owner.check(), nil)
        H.equal(c.owner.admit({ item_key = "cwv_es_musket" }), false)
        c.lookup[3], c.lookup.other = "other", 3; c.state._cwv_damage_profile_generation = 2
        H.equal(c.owner.check(), nil, "later valid producer generation is allowed")
    end)
    for _, edge in ipairs({ "profile", "numeric", "reverse", "source", "generation", "fallback" }) do
        for _, mode in ipairs({ "write", "readback" }) do
            local target, method = edge, mode
            H.test("#428 exact rollback " .. target .. " " .. method, function()
                local c = context({ adjust = function(opts, env, lookup, state)
                    setmetatable(env.DamageProfileTemplates, { __index = { [KEY] = "inherited-profile" } })
                    setmetatable(lookup, { __index = { [KEY] = 99 } })
                    setmetatable(state, { __index = { _cwv_wire_fallback_profile_id = 99 } })
                    if method == "write" then opts.write = function(t, k, v, tag)
                        rawset(t, k, v); if tag == target then error("injected commit write") end
                    end else opts.read = function(t, k, tag)
                        if tag == target then return "rejected" end; return rawget(t, k)
                    end end
                end })
                local before = raw_state(c)
                H.equal(c.owner.prepare(), NATIVE); all_unchanged(before)
                H.equal(c.owner.admit({ item_key = "cwv_es_musket_old", template = "old_musket_template" }), false)
            end)
        end
    end
    H.test("#428 foreign partial sparse and source state reject custom without adoption", function()
        local controls = {
            function(c) c.env.DamageProfileTemplates[KEY] = { foreign = true } end,
            function(c) c.lookup[2], c.lookup[KEY] = KEY, 2 end,
            function(c) c.lookup[3] = KEY end,
            function(c) c.state._cwv_damage_profile_wire_source[KEY] = NATIVE end,
            function(c) c.state._cwv_damage_profile_generation = 0/0 end,
            function(c) c.state._cwv_wire_fallback_profile_id = 999 end,
        }
        for _, alter in ipairs(controls) do
            local c = context(); alter(c); local before = raw_state(c)
            H.equal(c.owner.prepare(), NATIVE); all_unchanged(before)
            c.publish(); H.equal(c.action.damage_profile, NATIVE); H.equal(c.owner.check(), nil)
        end
    end)
    H.test("#428 no proven native means no template or admission", function()
        local controls = {
            function(c) c.env.DamageProfileTemplates[NATIVE] = nil end,
            function(c) c.env.DamageProfileTemplates[NATIVE] = { foreign = true } end,
            function(c) c.lookup[NATIVE] = nil end,
            function(c) c.lookup[NATIVE] = 1/0 end,
            function(c) c.lookup[1] = "foreign" end,
            function(c) c.opts.profiles = function() error("unreadable profiles") end end,
        }
        for _, alter in ipairs(controls) do
            local c = context(); alter(c); local before = raw_state(c)
            H.equal(c.owner.prepare(), nil); H.equal(c.publish(), nil); all_unchanged(before)
            H.equal(rawget(c.env.Weapons, "old_musket_template"), nil)
            H.equal(c.owner.admit({ item_key = "cwv_es_musket_old", template = "old_musket_template" }), false); H.truthy(c.owner.check())
        end
    end)
    H.test("#428 aliasing clone and throwing preflight leave exact source untouched", function()
        for _, clone in ipairs({ function(v) return v end, function(v) return { default_target = v.default_target } end,
                function() error("clone rejected") end }) do
            local c = context({ adjust = function(opts) opts.clone = clone end })
            local before = raw_state(c); local donor = c.env.table.clone(c.env.DamageProfileTemplates[NATIVE], true)
            H.equal(c.owner.prepare(), NATIVE); all_unchanged(before)
            H.deep_equal(c.env.DamageProfileTemplates[NATIVE], donor)
        end
    end)
    H.test("#428 retained tuple template and action tampering deny admission", function()
        local controls = {
            function(c) c.env.DamageProfileTemplates[KEY] = {} end,
            function(c) c.env.DamageProfileTemplates[KEY].cleave_distribution.attack = 7 end,
            function(c) c.lookup[KEY] = 1 end,
            function(c) c.state._cwv_damage_profile_wire_source[KEY] = "foreign" end,
            function(c) c.state._cwv_damage_profile_generation = 0 end,
            function(c) c.state._cwv_wire_fallback_profile_id = 2 end,
            function(c) c.env.Weapons.old_musket_template = {} end,
            function(c) c.template.actions.action_one.default = {} end,
            function(c) c.action.damage_profile = NATIVE end,
        }
        for _, alter in ipairs(controls) do
            local c = context(); c.publish(); alter(c)
            H.equal(c.owner.admit({ item_key = "cwv_es_musket_old", template = "old_musket_template" }), false); H.truthy(c.owner.check())
        end
    end)
    H.test("#428 template failure collision and unsupported reload cannot publish ownership", function()
        for _, mode in ipairs({ "write", "readback", "collision" }) do
            local c = context({ adjust = function(opts)
                if mode == "write" then opts.write = function(t, k, v, tag)
                    rawset(t, k, v); if tag == "template" then error("template write rejected") end
                end elseif mode == "readback" then opts.read = function(t, k, tag)
                    if tag == "template" then return nil end; return rawget(t, k)
                end end
            end })
            local key = c.owner.prepare(); local template = { actions = {} }; local action = { damage_profile = key }
            local foreign = {}; if mode == "collision" then c.env.Weapons.old_musket_template = foreign end
            H.equal(c.owner.publish_template(c.env.Weapons, template, { { action = action } }), false)
            H.equal(rawget(c.env.Weapons, "old_musket_template"), mode == "collision" and foreign or nil)
            H.truthy(c.owner.check())
        end
        local c = context(); c.publish()
        local fresh = run(read(prefix .. "_cwv_old_musket_shot_owner.lua"), c.env).new(c.opts)
        H.equal(fresh.prepare(), NATIVE, "fresh owner cannot adopt old custom state")
        H.equal(fresh.publish_template(c.env.Weapons, {}, {}), false); H.truthy(fresh.check())
    end)
    H.test("#428 latched firing degrades only still-owned field to proven native", function()
        local c = context(); local action = c.publish()
        local self = { current_action = action, action_start_t = 1, state = "waiting_to_shoot", time_to_shoot = 1.2 }
        c.env.DamageProfileTemplates[KEY] = nil
        H.truthy(c.owner.guard(self, 1.1)); H.equal(action.damage_profile, KEY, "no per-frame rewrite before due")
        H.truthy(c.owner.guard(self, 1.2)); H.equal(action.damage_profile, NATIVE)
        H.truthy(c.owner.guard(self, 1.3)); H.equal(self.current_action, action); H.equal(self.state, "waiting_to_shoot")
        local foreign = { damage_profile = KEY }; self.current_action = foreign
        H.truthy(c.owner.guard(self, 1.3)); H.equal(foreign.damage_profile, KEY)
    end)
    H.test("#428 denied trigger stays quarantined across repair until actual new start token", function()
        local c = context(); local action = c.publish()
        local custom, native = c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE]
        c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE] = nil, nil
        local self = { current_action = action, action_start_t = 2, state = "waiting_to_shoot", time_to_shoot = 2 }
        H.equal(c.owner.guard(self, 2), false); H.equal(action.damage_profile, KEY)
        c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE] = custom, native
        H.equal(c.owner.guard(self, 2.1), false); H.equal(self.current_action, action)
        self.action_start_t = 3; H.truthy(c.owner.guard(self, 3))
        action.damage_profile = "foreign"; self.action_start_t = 4
        H.equal(c.owner.guard(self, 4), false); H.equal(action.damage_profile, "foreign")
    end)
    H.test("#428 guard reader errors and failed action fallback quarantine without mutation", function()
        for _, mode in ipairs({ "reader", "write", "readback", "invalid_start", "invalid_time", "invalid_schedule" }) do
            local c = context({ adjust = function(opts)
                if mode == "write" then opts.write = function(t, k, v, tag)
                    rawset(t, k, v); if tag == "action_fallback" then error("field rejected") end
                end elseif mode == "readback" then opts.read = function(t, k, tag)
                    if tag == "action_fallback" then return nil end; return rawget(t, k)
                end end
            end })
            local action = c.publish(); c.env.DamageProfileTemplates[KEY] = nil
            if mode == "reader" then c.opts.lookup = function() error("reader rejected") end end
            local self = { current_action = action, action_start_t = mode == "invalid_start" and 0/0 or 1, state = "shooting" }
            if mode == "invalid_schedule" then self.state = "waiting_to_shoot" end
            local state = self.state
            H.equal(c.owner.guard(self, mode == "invalid_time" and 0/0 or 1), false); H.equal(action.damage_profile, KEY)
            H.equal(self.current_action, action); H.equal(self.state, state)
        end
    end)

    -- Core constructor/firing proof uses required tracked exact native snapshots.
    -- An external checkout is additional provenance, never a core test prerequisite.
    local native_root = os.getenv("VT2_SOURCE_ROOT") or (root .. "/../Vermintide-2-Source-Code")
    local MeleeNative = dofile(root .. "/qa/lua/fixtures/cwv_old_musket_native_melee.lua")
    local NativeSnapshot = MeleeNative.snapshot(root)
    local native_available = MeleeNative.available(root)
    local function installed(alter)
        local c = context(); local env, om = c.env, c.state
        env._om = om
        env.ActionTemplates = { wield = {}, reload = {}, action_inspect = {} }
        env.BreedCategory = { Armored=16, Berserker=4, Boss=8, Infantry=1, Shielded=2, Special=64, SuperArmor=32 }
        env.DamageTypes = { ARMOR_PIERCING=1, CLEAVE=2, DAMAGE=5, SPEED=3, STAGGER=4 }
        env.bit = { bor = function(...)
            local sum, seen = 0, {}; for _, value in ipairs({...}) do
                assert((value==4 or value==64 or value==16 or value==2) and not seen[value]); seen[value]=true; sum=sum+value
            end; return sum
        end }
        env.AttachmentNodeLinking = { rifles = {}, polearm = {} }; env.printf = function(...) c.logs[#c.logs + 1] = { ... } end
        env.Weapons = run(NativeSnapshot.handguns, env, "tracked-native6.13-complete-handguns")
        MeleeNative.load(env, root, c.lookup)
        env.NetworkLookup = { damage_profiles = c.lookup, item_names = {} }
        env.ActionHandgun = { client_owner_post_update = function() end }
        env.ItemMasterList = { es_handgun = { name = "es_handgun", key = "es_handgun", template = "handgun_template_1",
            item_type = "es_handgun", slot_type = "ranged", can_wield = {} } }
        local function load(name) return run(read(prefix .. name .. ".lua"), env, name) end
        c.load = load
        local entry = read(prefix .. "character_weapon_variants.lua")
        local a = assert(entry:find("function _om._record_cwv_dp_source(", 1, true))
        local b = assert(entry:find("\nend\n", a, true)) + 4
        run(entry:sub(a, b), env, "actual-entry-source-recorder")
        om.musket_ammo_pool_policy = load("_cwv_musket_ammo_pool")
        local hooks, count, loads = {}, 0, {}
        local mod = { info = function() end, warning = function() end, error = function() end,
            get = function() return false end, _cwv_old_musket_interrupt = load("_cwv_old_musket_interrupt") }
        local function hook(_, class, method, fn)
            count = count + 1; local key = tostring(class) .. ":" .. method
            H.equal(hooks[key], nil, "actual singleton hook duplicated"); hooks[key] = fn
        end
        mod.hook, mod.hook_safe = hook, hook
        mod.dofile = function(_, path)
            local name = assert(path:match("/([^/]+)$"))
            loads[name] = (loads[name] or 0) + 1
            if name == "_lib_network_lookup" then return c.opts.lookup_helper end
            return load(name)
        end
        env.get_mod = function() return nil end
        c.mod = mod
        if alter then alter(c) end
        local call_start = assert(entry:find('local _variant_install = mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_shot_owner")', 1, true))
        local call_end = assert(entry:find("\n\n", call_start, true))
        local call = entry:sub(call_start, call_end-1)
        local capsule = run("return function(mod, _om, _dbg)\n" .. call .. "\nreturn _variant_install end",
            env, "actual-entry-musket-private-binding")(mod, om, function() end)
        H.equal(loads._cwv_old_musket_shot_owner, 1); H.equal(loads._lib_network_lookup, 1)
        c.mod, c.hooks, c.capsule, c.hook_count, c.entry, c.loads = mod, hooks, capsule, count, entry, loads
        local template = env.Weapons.old_musket_template
        c.action = template and template.actions and template.actions.action_one.default
        return c
    end
    H.test_if(native_available, "#428 complete installer selects owned or native and denies neither", function()
        local good = installed()
        H.equal(good.action.damage_profile, KEY); H.equal(good.lookup[KEY], 7)
        H.equal(good.lookup[6], "cwv_musket_shot", "unchanged earlier publisher follows native input IDs")
        H.equal(good.state._cwv_damage_profile_generation, 9)
        H.equal(good.state._cwv_wire_fallback_profile_id, 1)
        H.truthy(good.capsule.admit_old_musket({ item_key = "cwv_es_musket_old", template = "old_musket_template" }))
        H.equal(good.capsule.check_old_musket(), nil)
        local fallback = installed(function(c) c.env.DamageProfileTemplates[KEY] = { foreign = true } end)
        H.equal(fallback.action.damage_profile, NATIVE); H.equal(rawget(fallback.lookup, KEY), nil)
        H.equal(fallback.capsule.check_old_musket(), nil)
        local denied = installed(function(c) c.env.DamageProfileTemplates[NATIVE] = nil end)
        H.equal(denied.action, nil); H.equal(rawget(denied.env.Weapons, "old_musket_template"), nil)
        H.equal(denied.capsule.admit_old_musket({ item_key = "cwv_es_musket_old" }), false)
        H.truthy(denied.capsule.check_old_musket()); H.equal(denied.hook_count, good.hook_count)
        H.equal(fallback.hook_count, good.hook_count)
        local foreign = {}; local collision = installed(function(c) c.env.Weapons.old_musket_template = foreign end)
        H.equal(collision.env.Weapons.old_musket_template, foreign)
        H.equal(collision.capsule.admit_old_musket({ item_key = "cwv_es_musket_old" }), false)
    end, "source-qualified native handgun checkout unavailable")
    H.test_if(native_available, "#428 actual constructor never exposes Old Musket when native closure is absent", function()
        for _, alter in ipairs({
            function(row) row.env.DamageProfileTemplates[NATIVE] = nil end,
            function(row) row.env.NetworkLookup.damage_profiles = nil end,
            function(row) row.lookup[NATIVE] = nil end,
            function(row) row.lookup[1] = "foreign" end,
        }) do
            local c = installed(alter)
            H.equal(c.action, nil)
            H.equal(rawget(c.env.Weapons, "old_musket_template"), nil, "a named template without a proven shot must not be public")
        end
    end, "source-qualified native handgun checkout unavailable")

    local function native_firing(c, extra)
        local env, ledger = c.env, { native = 0, ammo = 0, hit = 0, trail = 0, audio = 0 }
        c.state._old_musket_publish_fire = function() ledger.audio = ledger.audio + 1; return true end
        local vec = {}; vec.__add = function() return setmetatable({}, vec) end
        vec.__sub, vec.__mul = vec.__add, vec.__add
        local position = setmetatable({}, vec)
        env.Vector3 = { length = function() return 1 end }
        env.Quaternion = { forward = function() return position end }
        env.World = { get_data = function() return {} end }
        env.PhysicsWorld = { immediate_raycast_actors = function() return { { position } } end }
        local fp = { get_projectile_start_position_rotation = function() return position, {} end,
            play_hud_sound_event = function() ledger.audio = ledger.audio + 1 end,
            reset_aim_assist_multiplier = function() end }
        env.ScriptUnit = { has_extension = function() return false end,
            extension = function(_, system) H.equal(system, "first_person_system"); return fp end }
        env.Managers = { player = { owner = function() return { bot_player = true } end },
            input = { is_device_active = function() return false end },
            state = { entity = { system = function() return { alert_enemies_within_range = function() end } end } } }
        env.POSITION_LOOKUP = {}
        env.DamageUtils = { process_projectile_hit = function(_, _, _, _, _, action)
            local id = rawget(c.lookup, action.damage_profile)
            assert(type(id) == "number" and rawget(c.lookup, id) == action.damage_profile, "native strict lookup would fail")
            assert(type(rawget(env.DamageProfileTemplates, action.damage_profile)) == "table", "native profile missing")
            ledger.hit = ledger.hit + 1
        end }
        env.Unit = { alive = function() return true end,
            set_flow_variable = function() end, flow_event = function() ledger.trail = ledger.trail + 1 end }
        run(NativeSnapshot.handgun_post_update, env, "exact-tracked-native-handgun-post-update")
        local native = env.ActionHandgun.client_owner_post_update
        local self = { current_action = c.action, action_start_t = 1, state = "waiting_to_shoot", time_to_shoot = 1,
            weapon_unit = {}, owner_unit = {}, ammo_usage = 1, owner_buff_extension = {},
            ammo_extension = { use_ammo = function() ledger.ammo = ledger.ammo + 1 end },
            _update_extra_shots = function() return extra == true end }
        local wrapper = assert(c.hooks["ActionHandgun:client_owner_post_update"])
        local function fire(t)
            return wrapper(function(...) ledger.native = ledger.native + 1; return native(...) end,
                self, 0.01, t, {}, false) -- can_damage=false is deliberately NOT relied upon.
        end
        return self, ledger, fire
    end
    H.test_if(native_available, "#428 actual installed wrapper contains native ammo hit trail audio and pending extra shot", function()
        local good = installed(); local _, healthy, fire = native_firing(good)
        fire(1); H.equal(healthy.native, 1); H.equal(healthy.ammo, 1); H.equal(healthy.hit, 1)
        H.equal(healthy.trail, 2); H.equal(healthy.audio, 1)
        local fallback = installed(); local _, degraded, fallback_fire = native_firing(fallback)
        fallback.env.DamageProfileTemplates[KEY] = nil; fallback_fire(1)
        H.equal(fallback.action.damage_profile, NATIVE); H.equal(degraded.hit, 1)
        local c = installed(); local self, ledger, denied_fire = native_firing(c, true)
        local custom, native = c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE]
        c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE] = nil, nil
        denied_fire(1); H.deep_equal(ledger, { native=0, ammo=0, hit=0, trail=0, audio=0 })
        H.equal(self.current_action, c.action); H.equal(self.state, "waiting_to_shoot")
        c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE] = custom, native
        denied_fire(1.2); H.equal(ledger.native, 0, "denied trigger cannot discharge after repair")
        self.action_start_t = 2; denied_fire(2); H.equal(ledger.hit, 1)
        H.equal(self.state, "waiting_to_shoot"); H.equal(self.extra_buff_shot, true)
        c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE] = nil, nil
        denied_fire(2.2); H.equal(ledger.hit, 1, "pending extra shot contained")
        c.env.DamageProfileTemplates[KEY], c.env.DamageProfileTemplates[NATIVE] = custom, native
        denied_fire(2.3); H.equal(ledger.hit, 1, "pending extra cannot fire on repair")
    end, "source-qualified native handgun checkout unavailable")

    local function private_items(c)
        local om, load = c.state, c.load
        om.greataxe, om.dawi_maces = load("_cwv_greataxe"), load("_cwv_dawi_maces")
        om.crowbill_family, om.crowbill_hammer_mode = load("_cwv_crowbill_family"), load("_cwv_crowbill_hammer_mode")
        om.crowbill_runtime = load("_cwv_crowbill_runtime")
        local definitions = load("_cwv_variant_catalog")({ om = om }).definitions
        local old, control
        for _, def in ipairs(definitions) do
            if def.item_key == "cwv_es_musket_old" then old = def end
            if def.item_key == "cwv_es_axe_shield" then control = def end
        end
        assert(old and control)
        local source = read(prefix .. "_cwv_item_registration_owner.lua")
        local a = assert(source:find("local function install(mod, ctx)", 1, true))
        local b = assert(source:find("local function _auto_register_all()", a, true))
        local export = assert(source:find("_om.item_registration = {", b, true))
        -- Exact owner prefix/header/builder plus exact export, no goto lowering.
        -- The unchanged complete deferred callback is NOT executable by PUC5.1.
        local builder_install = run(source:sub(a, b-1) .. source:sub(export), c.env, "exact-registration-prefix-and-export")
        local original_dofile = c.mod.dofile
        c.mod.dofile = function(self, path)
            if path:match("/_cwv_item_registration_owner$") then return builder_install end
            return original_dofile(self, path)
        end
        c.mod._cwv_acquisition = load("_cwv_acquisition")
        c.env.ItemMasterList.dr_shield_axe = { name = "dr_shield_axe", item_type = "dr_shield_axe", can_wield = {} }
        local entry = c.entry
        a = assert(entry:find('_variant_install =\n\tmod:dofile("scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner")', 1, true))
        b = assert(entry:find("\n-- Skin/illusion registrars", a, true))
        local bootstrap = entry:sub(a, b-1)
        a = assert(entry:find("_variant_install = _variant_install.after_skins(_custom_skin_keys, _rt_register)", b, true))
        b = assert(entry:find("\n", a, true))
        local phases = entry:sub(a, b-1)
        a = assert(entry:find('_variant_install.install_items(mod:dofile("scripts/mods/character_weapon_variants/_cwv_item_registration_owner")', b, true))
        b = assert(entry:find("\n})", a, true)) + 3
        local items = entry:sub(a, b)
        local checks = {}
        local bind = run("return function(mod, _om, _variant_definitions, _variant_install, _rt_register)\n"
            .. "local _custom_skin_keys, _dbg, _dbg_alert = {}, function() end, function() end\n"
            .. bootstrap .. "\n" .. phases .. "\nreturn function()\n" .. items .. "\nend end",
            c.env, "exact-entry-bootstrap-items-private-wiring")
        local install_items = bind(c.mod, om, { old, control }, c.capsule, function(name, fn) checks[name] = fn end)
        -- Alter only the now-public capsule after the lexical bind. A private
        -- retained predicate/check must not reread this mutable table.
        c.capsule.admit_old_musket, c.capsule.check_old_musket = function() return true end, function() end
        c.capsule.network_lookup = { register = function() error("foreign helper must not be reread") end }
        install_items()
        H.equal(c.loads._cwv_old_musket_shot_owner, 1); H.equal(c.loads._lib_network_lookup, 1)
        return old, control, om.item_registration.build_entry, assert(checks.issue428_old_musket_construction)
    end
    H.test_if(native_available, "#428 actual private bootstrap admission and seed reject authority loss before publication", function()
        local c = installed(); local old, control, build, check = private_items(c)
        H.equal(check(), nil)
        local entry = assert(build(old)); H.equal(entry.template, "old_musket_template")
        local seed = assert(c.mod._cwv_acquisition.build_seed(old, build,
            function(v) return c.env.table.clone(v, true) end, function() return false end))
        H.equal(seed.mod_data.power_level, 5); H.truthy(build(control), "unrelated definition unchanged")
        c.env.DamageProfileTemplates[KEY] = nil
        local iml, names = shape(c.env.ItemMasterList), shape(c.env.NetworkLookup.item_names)
        H.equal(build(old), nil); H.equal(c.state.item_registration.registered_keys[old.item_key], nil)
        H.equal(c.mod._cwv_acquisition.build_seed(old, build,
            function(v) return c.env.table.clone(v, true) end, function() return false end), nil)
        H.truthy(check(), "named installed check retains original actual owner")
        H.truthy(build(control)); unchanged(iml); unchanged(names)
        H.equal(c.state._cwv_blacksmith_seed_ids, nil); H.equal(c.mod._cwv_blacksmith_seed_identity, nil)
        local foreign = {}; c.env.ItemMasterList[old.item_key] = foreign
        H.equal(build(old), nil); H.equal(c.env.ItemMasterList[old.item_key], foreign)
    end, "source-qualified native handgun checkout unavailable")
    H.test_if(native_available, "#428 actual private bootstrap no admission on missing constructor or foreign IML", function()
        local denied = installed(function(c) c.env.DamageProfileTemplates[NATIVE] = nil end)
        local old, control, build, check = private_items(denied)
        H.equal(build(old), nil); H.truthy(build(control)); H.truthy(check())
        H.equal(rawget(denied.env.ItemMasterList, old.item_key), nil)
        local foreign = {}; local collision = installed()
        old, control, build, check = private_items(collision)
        collision.env.ItemMasterList[old.item_key] = foreign
        H.equal(build(old), nil); H.equal(collision.env.ItemMasterList[old.item_key], foreign)
        H.truthy(build(control))
        local unguarded = installed(function(c) c.env.ActionHandgun = nil end)
        old, control, build, check = private_items(unguarded)
        H.equal(build(old), nil); H.truthy(build(control)); H.truthy(check())
    end, "source-qualified native handgun checkout unavailable")
    return { installed = installed, private_items = private_items, read = read, run = run, shape = shape, unchanged = unchanged, native_root = native_root, available = native_available }
end
