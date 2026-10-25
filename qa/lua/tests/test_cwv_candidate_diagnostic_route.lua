return function(H, repo_root)
    local base = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local function clone(v, seen)
        if type(v) ~= "table" then return v end
        seen = seen or {}; if seen[v] then return seen[v] end
        local c = {}; seen[v] = c
        for k, value in pairs(v) do c[clone(k, seen)] = clone(value, seen) end
        return c
    end
    local function donor(label)
        return { state_machine = label, wield_anim = "to_" .. label, actions = {
            action_one = {
                default = { kind = "melee_start", anim_event = "charge",
                    allowed_chain_actions = {
                        { action = "action_one", sub_action = "light", input = "action_one_release" },
                        { action = "action_one", sub_action = "heavy", input = "action_one_hold" },
                        { action = "action_two", sub_action = "default", input = "action_two_hold" },
                    } },
                light = { kind = "sweep", anim_event = "light" },
                heavy = { kind = "sweep", anim_event = "heavy" },
                push = { kind = "push", anim_event = "push", allowed_chain_actions = {
                    { action = "action_one", sub_action = "push_attack", input = "action_one_hold" },
                } },
                push_attack = { kind = "sweep", anim_event = "push_attack" },
            },
            action_two = { default = { kind = "block", anim_event = "parry_pose",
                anim_end_event = "parry_finished", weapon_action_hand = "left",
                allowed_chain_actions = {
                    { action = "action_one", sub_action = "push", input = "action_one" },
                    { action = "action_one", sub_action = "default", input = "action_two_release" },
                } } },
        } }
    end
    local function fixture()
        local hooks, counts, checks, native_reads, live_observations = {}, {}, {}, 0, 0
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.Managers = { player = { local_player = function()
            native_reads = native_reads + 1; return nil
        end } }
        env.printf = function() error("probe reached live logger") end
        local function load(name)
            local chunk = assert(loadfile(repo_root .. base .. name .. ".lua"))
            setfenv(chunk, env); return chunk()
        end
        local policy = load("_cwv_combat_styles")
        local weapons = { es_deus_01_template = donor("empire"),
            one_handed_spears_shield_template = donor("elven"),
            one_handed_sword_shield_template_1 = {}, one_handed_sword_shield_template_2 = {} }
        local ports = assert(policy.build_spear_shield_templates(weapons, clone))
        for key, value in pairs(ports) do weapons[key] = value end
        env.Weapons = weapons
        local mod = { _cwv_dev_anim_picker = { resolve = function() end } }
        local helper_loads = 0
        mod.dofile = function(_, path)
            if path:find("_cwv_candidate_diagnostic_contract", 1, true) then helper_loads = helper_loads + 1 end
            return load(assert(path:match("([^/]+)$")))
        end
        local function hook(_, class, method, callback)
            local key = class .. "." .. method
            hooks[key], counts[key] = callback, (counts[key] or 0) + 1
        end
        mod.hook, mod.hook_safe = hook, hook
        local live = { diagnostic_seen = { keep = true }, diagnostic_counts = { keep = 7 },
            observe_candidate_action = function() live_observations = live_observations + 1 end }
        local dispatch = load("_cwv_remote_audio_dispatch")
        local om = { greataxe = { ANIM_REMAP_3P = {} }, remote_audio_dispatch = dispatch,
            combat_style_policy = policy, combat_styles = live }
        om.cross_access = load("_cwv_cross_access")(mod, {
            om = om, dbg = function() error("probe reached debug logger") end,
            es_all_careers = {}, wh_all_careers = {},
        })
        H.equal(counts["WeaponUnitExtension._play_3p_anim"], 1)
        H.equal(om.cross_access.networked_3p_anim_callback,
            hooks["WeaponUnitExtension._play_3p_anim"], "probe owner differs from installed callback")
        local entry_file = assert(io.open(repo_root .. base .. "character_weapon_variants.lua", "rb"))
        local entry = entry_file:read("*a"); entry_file:close()
        local expression = assert(entry:match("\n\tcandidate_diagnostic_contract = ([^\n]+)"))
        local context = assert(loadstring("local mod = ...\nreturn { candidate_diagnostic_contract = "
            .. expression .. "}", "@issue645-actual-entry-dependency"))
        setfenv(context, env)
        local ctx = context(mod)
        local contract = ctx.candidate_diagnostic_contract
        H.equal(helper_loads, 1, "diagnostic contract must be manifest-loaded once")
        local f = assert(io.open(repo_root .. base .. "_cwv_regression_identity.lua", "rb"))
        local source = f:read("*a"); f:close()
        local first = assert(source:find('_rt_register("issue645_reciprocal_style_descriptors", function()', 1, true))
        local last = assert(source:find("\nend)", first, true)) + 4
        local chunk = assert(loadstring("return function(mod, _om, ctx, _rt_register)\n"
            .. source:sub(first, last) .. "\nend", "@issue645-production-registration"))
        setfenv(chunk, env)
        chunk()(mod, om, ctx, function(name, callback) checks[name] = callback end)
        return { check = checks.issue645_reciprocal_style_descriptors, om = om,
            policy = policy, contract = contract, weapons = weapons, hooks = hooks,
            dispatch = dispatch, env = env, live = live,
            native_reads = function() return native_reads end,
            context = ctx, helper_loads = function() return helper_loads end,
            live_observations = function() return live_observations end }
    end
    local function rejected(fx, word)
        local result = fx.check()
        H.equal(type(result), "string", "named check falsely passed disconnected source")
        if word then H.truthy(result:find(word, 1, true), result) end
    end
    H.test("CWV #645 named check executes actual installed candidate route without live state", function()
        local fx, calls = fixture(), 0
        local actual = fx.om._cross_access_observe_live
        fx.om._cross_access_observe_live = function(...)
            calls = calls + 1; return actual(...)
        end
        H.equal(fx.check(), nil)
        H.equal(fx.helper_loads(), 1, "running the check must not reload its child")
        H.truthy(calls > fx.policy.DIAGNOSTIC_EVENT_CAP)
        H.equal(fx.native_reads(), 0)
        H.equal(fx.live_observations(), 0)
        H.deep_equal(fx.live.diagnostic_seen, { keep = true })
        H.deep_equal(fx.live.diagnostic_counts, { keep = 7 })
    end)
    H.test("CWV #645 missing manifest child fails visibly instead of loading again", function()
        local fx = fixture()
        fx.context.candidate_diagnostic_contract = nil
        rejected(fx, "contract missing")
        H.equal(fx.helper_loads(), 1)
    end)
    H.test("CWV #645 named check rejects disconnected live observer", function()
        local fx = fixture(); fx.om._cross_access_observe_live = function() end
        rejected(fx, "disconnected")
    end)
    H.test("CWV #645 named check rejects dispatch that drops observation", function()
        local fx = fixture()
        fx.dispatch.invoke = function(func, self, event, ...) return func(self, event, ...) end
        rejected(fx, "disconnected")
    end)
    H.test("CWV #645 named check rejects wrong forwarded event", function()
        local fx = fixture(); local actual = fx.om._cross_access_observe_live
        fx.om._cross_access_observe_live = function() return actual("wrong_event") end
        rejected(fx, "context")
    end)
    H.test("CWV #645 named check rejects missing installed marker", function()
        local fx = fixture(); fx.om.cross_access.networked_3p_remap_installed = false
        rejected(fx, "owner missing")
    end)
    H.test("CWV #645 named check rejects missing returned probe", function()
        local fx = fixture(); fx.om.cross_access.probe_candidate_action = nil
        rejected(fx, "owner missing")
    end)
    H.test("CWV #645 named check rejects missing callback identity", function()
        local fx = fixture(); fx.om.cross_access.networked_3p_anim_callback = nil
        rejected(fx, "owner missing")
    end)
    H.test("CWV #645 named probe restores after observer exception", function()
        local fx = fixture()
        local ok = fx.om.cross_access.probe_candidate_action({
            observe_candidate_action = function() error("probe_observer_error") end },
            "we_2h_axe", "we_maidenguard", "attack", function() error("not reached") end)
        H.equal(ok, false)
        local called = 0
        fx.hooks["WeaponUnitExtension._play_3p_anim"](function() called = called + 1 end,
            {}, "normal", nil, {}, false, 1)
        H.equal(called, 1)
        H.equal(fx.native_reads(), 1, "stale detached body bypassed live reader")
        H.equal(fx.check(), nil)
    end)
    H.test("CWV #645 probe restores after delegate exception and preserves return arity", function()
        local fx = fixture(); local probe = fx.om.cross_access.probe_candidate_action
        local runtime = { observe_candidate_action = function() end }
        local ok = probe(runtime, "we_2h_axe", "we_maidenguard", "attack",
            function() error("probe_delegate_error") end)
        H.equal(ok, false)
        local function capture(...) return select("#", ...), { ... } end
        local count, out = capture(probe(runtime, "we_2h_axe", "we_maidenguard", "attack",
            function() return nil, "native", nil end))
        H.equal(count, 4); H.equal(out[1], true); H.equal(out[2], nil)
        H.equal(out[3], "native"); H.equal(out[4], nil)
        H.equal(fx.check(), nil)
    end)
    H.test("CWV #645 detached probe rejects reentrancy without losing outer context", function()
        local fx = fixture(); local probe, nested = fx.om.cross_access.probe_candidate_action
        local runtime = { observe_candidate_action = function()
            nested = { probe({}, "x", "y", "z", function() end) }
        end }
        H.equal(probe(runtime, "we_2h_axe", "we_maidenguard", "attack", function() end), true)
        H.equal(nested[1], false); H.truthy(nested[2]:find("busy", 1, true))
        H.equal(fx.check(), nil)
    end)
    H.test("CWV #645 graph contract rejects absent block", function()
        local fx = fixture()
        fx.weapons[fx.policy.EMPIRE_SPEAR_SHIELD_TEMPLATE].actions.action_two.default = nil
        rejected(fx, "block entry")
    end)
    H.test("CWV #645 graph contract rejects missing light heavy or push attack", function()
        for _, key in ipairs({ "default", "light", "heavy", "push", "push_attack" }) do
            local fx = fixture()
            fx.weapons[fx.policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_one[key] = nil
            rejected(fx, "node missing")
        end
    end)
    H.test("CWV #645 graph contract rejects block release event drift", function()
        local fx = fixture()
        fx.weapons[fx.policy.EMPIRE_SPEAR_SHIELD_TEMPLATE].actions.action_two.default.anim_end_event = "wrong"
        rejected(fx, "anim_end_event")
    end)
    H.test("CWV #645 graph contract rejects block push chain drift", function()
        local fx = fixture()
        fx.weapons[fx.policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_two.default.allowed_chain_actions[1].sub_action = "heavy"
        rejected(fx, "sub_action")
    end)
    H.test("CWV #645 graph contract rejects first-person state machine drift", function()
        local fx = fixture()
        fx.weapons[fx.policy.EMPIRE_SPEAR_SHIELD_TEMPLATE].state_machine = "wrong"
        rejected(fx, "first-person routing")
    end)
    H.test("CWV #645 graph contract allows unrelated timing balance changes", function()
        local fx = fixture()
        fx.weapons[fx.policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_one.light.total_time = 1.2
        H.equal(fx.check(), nil)
    end)

    local native_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/"
    local f = io.open(native_root .. "1h_spears_shield.lua", "rb")
    local native_present = f ~= nil; if f then f:close() end
    H.test_if(native_present, "native weapon-authored Spear and Shield donor graphs remain intact", function()
            local fx = fixture()
            -- Only weapon-authored nodes are under test. Shared ActionTemplates
            -- and engine/vector/attachment objects are not engine coverage.
            local env = setmetatable({ ActionTemplates = {},
                Vector3Box = function(...) return { ... } end,
                DamageTypes = { ARMOR_PIERCING = 1, CLEAVE = 2, SPEED = 3,
                    STAGGER = 4, DAMAGE = 5 }, AttachmentNodeLinking = {
                one_handed_melee_weapon = { right = {} }, shield = {},
            } }, { __index = _G })
            local weapons = {}
            for _, file in ipairs({ "es_deus_01", "1h_spears_shield" }) do
                local input = assert(io.open(native_root .. file .. ".lua", "rb"))
                local text = input:read("*a"); input:close()
                -- Stock Lua 5.1 does not consume the extraction's UTF-8 BOM.
                if text:sub(1, 3) == string.char(239, 187, 191) then text = text:sub(4) end
                local chunk = assert(loadstring(text, "@" .. native_root .. file .. ".lua"))
                setfenv(chunk, env)
                for key, value in pairs(chunk()) do weapons[key] = value end
            end
            local ports = assert(fx.policy.build_spear_shield_templates(weapons, clone))
            for key, value in pairs(ports) do weapons[key] = value end
            H.equal(fx.contract.check_spear_graphs(fx.policy, weapons), nil)
            weapons[fx.policy.ELVEN_SPEAR_SHIELD_TEMPLATE].actions.action_two.default.anim_event = "broken"
            H.truthy(fx.contract.check_spear_graphs(fx.policy, weapons))
        end, "external native source absent")
end
