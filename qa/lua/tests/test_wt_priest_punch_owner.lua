-- Actual #428 Priest owner and complete balance-module behavior, no engine globals.
return function(H, repo_root)
    local KEY, SOURCE = "wt_priest_punch_buffed", "light_blunt_smiter_stab"
    local FALLBACK, OWNER = "_wt431_custom_profile_fallback", "_wt428_priest_punch_owner"
    local CALLBACK, TEMPLATE = "wt_apply_priest_punch_buff", "two_handed_hammer_priest_template"
    local function clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local result = {}
        seen[value] = result
        for key, item in next, value do result[key] = clone(item, seen) end
        return result
    end
    local function snapshot(roots)
        local rows, seen = {}, {}
        local function capture(value)
            if type(value) ~= "table" or seen[value] then return end
            seen[value] = true
            local raw = {}
            for key, item in next, value do raw[key] = item end
            rows[#rows + 1] = { target = value, raw = raw, meta = getmetatable(value) }
            for _, item in next, raw do capture(item) end
        end
        for _, root in ipairs(roots) do capture(root) end
        return function()
            for _, row in ipairs(rows) do
                H.equal(getmetatable(row.target), row.meta, "metatable identity")
                local count = 0
                for key, item in next, row.target do
                    H.equal(item, rawget(row.raw, key), "raw value/identity " .. tostring(key))
                    count = count + 1
                end
                local expected = 0
                for key, item in next, row.raw do
                    H.equal(rawget(row.target, key), item, "raw presence " .. tostring(key))
                    expected = expected + 1
                end
                H.equal(count, expected, "raw cell count")
            end
        end
    end
    local function fixture(stream, options)
        options = options or {}
        local f = { stream = stream, enabled = options.enabled == true, allowed = options.allowed == true,
            loaded = {}, warnings = {}, settings_calls = 0 }
        f.globals = setmetatable({}, { __index = _G })
        f.globals._G = f.globals
        f.globals.table = setmetatable({ clone = function(value) return clone(value) end }, { __index = table })
        f.powers = { default_ref = { attack_template = "light_blunt_fencer", power_distribution = { attack = 0.125, impact = 0.25 } },
            targets_ref = { { attack_template = "heavy_blunt_fencer", power_distribution = { attack = 0.375, impact = 0.5 } } } }
        f.donor = { charge_value = "light_attack", armor_modifier = { attack = { 1, 0.5, 1 }, impact = { 1, 1, 1 } },
            default_target = options.references and "default_ref" or clone(f.powers.default_ref),
            targets = options.references and "targets_ref" or clone(f.powers.targets_ref) }
        f.profiles = { [SOURCE] = f.donor,
            shot_sniper = { default_target = { power_distribution_near = { attack = 1, impact = 0.5 } },
                cleave_distribution = { attack = 0.3, impact = 0.3 } } }
        f.lookup = { "n/a", SOURCE, "shot_sniper", ["n/a"] = 1, [SOURCE] = 2, shot_sniper = 3 }
        f.first, f.second = { damage_profile = SOURCE }, { damage_profile = SOURCE }
        f.actions = { action_one = { punch = f.first }, action_two = { punch = f.second },
            unaffected = { default = { damage_profile = "other-native" } } }
        f.template = { actions = f.actions }
        f.weapons = { [TEMPLATE] = f.template }
        f.network = { damage_profiles = f.lookup }
        f.globals.DamageProfileTemplates, f.globals.PowerLevelTemplates = f.profiles, f.powers
        f.globals.NetworkLookup, f.globals.Weapons = f.network, f.weapons
        f.globals.printf = function() end
        f.mod = { _wt = { dbg = function() end } }
        f.mod.get = function(_, setting)
            f.settings_calls = f.settings_calls + 1
            if f.setting_error then error(f.setting_error) end
            return setting == "wt_priest_punch_buff" and f.enabled
        end
        f.mod._wt431_profiles_allowed = function()
            if f.parity_error then error(f.parity_error) end
            return f.allowed
        end
        f.mod.warning = function(_, message) f.warnings[#f.warnings + 1] = message end
        f.mod.info = function() end
        f.mod.command = function() end
        f.globals.get_mod = function(id) H.equal(id, stream.id); return f.mod end
        f.mod.dofile = function(_, name)
            f.loaded[#f.loaded + 1] = name
            local file = name:match("([^/]+)$") .. ".lua"
            local chunk = assert(loadfile(stream.dir .. file))
            setfenv(chunk, f.globals)
            return chunk()
        end
        f.module = f.mod:dofile("scripts/mods/" .. stream.ns .. "/_wt_priest_punch_owner")
        function f:install(deps)
            deps = deps or {}
            deps.globals = self.globals
            return self.module.install(self.mod, deps)
        end
        function f:balance()
            local chunk = assert(loadfile(stream.dir .. "_wt_weapon_balance_patches.lua"))
            setfenv(chunk, self.globals)
            return chunk()
        end
        function f:unchanged()
            return snapshot({ self.mod, self.profiles, self.powers, self.network, self.weapons })
        end
        return f
    end
    local streams = {
        { id = "wt", ns = "weapon_tweaker", dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/" },
        { id = "wt_dev", ns = "weapon_tweaker_dev", dir = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/" },
    }
    local wire = assert(loadfile(streams[1].dir .. "_wt431_wire_contract.lua"))()
    local function rejected(f, deps)
        local unchanged = f:unchanged()
        local owner, reason = f:install(deps)
        H.equal(owner, nil)
        H.truthy(type(reason) == "string" and reason ~= "")
        unchanged()
        return reason
    end
    for _, stream in ipairs(streams) do
        local prefix = stream.id .. " Priest: "
        for _, references in ipairs({ false, true }) do
            H.test(prefix .. "complete balance boot preserves append order and content " .. tostring(references), function()
                local f = fixture(stream, { references = references, enabled = true, allowed = true })
                local native = snapshot({ f.donor, f.powers })
                f:balance()
                H.equal(f.lookup.wt_authentic_pistol, 4)
                H.equal(f.lookup[4], "wt_authentic_pistol")
                H.equal(f.lookup[KEY], 5)
                H.equal(f.lookup[5], KEY)
                H.equal(f.mod[FALLBACK][KEY], SOURCE)
                H.equal(f.mod[FALLBACK].wt_authentic_pistol, "shot_sniper")
                H.equal(f.first.damage_profile, KEY)
                H.equal(f.second.damage_profile, KEY)
                local profile = f.profiles[KEY]
                H.equal(profile.default_target.power_distribution.attack, 0.25)
                H.equal(profile.default_target.power_distribution.impact, 0.75)
                H.equal(profile.targets[1].power_distribution.attack, 0.75)
                H.equal(profile.targets[1].power_distribution.impact, 1.5)
                H.deep_equal(profile.armor_modifier, f.donor.armor_modifier)
                H.truthy(profile.armor_modifier ~= f.donor.armor_modifier)
                H.truthy(wire.build_wire_identity(f.mod[FALLBACK], f.lookup, f.profiles))
                H.truthy(wire.capture_catalog(f.mod[FALLBACK], f.lookup, f.profiles))
                local saw_owner, saw_helper = false, false
                for _, path in ipairs(f.loaded) do
                    if path == "scripts/mods/" .. stream.ns .. "/_wt_priest_punch_owner" then saw_owner = true end
                    if path == "scripts/mods/" .. stream.ns .. "/_lib_network_lookup" then saw_helper = true end
                end
                H.truthy(saw_owner and saw_helper)
                native()
            end)
        end
        H.test(prefix .. "off and early parity still register but never repoint", function()
            for _, flags in ipairs({ { false, true }, { true, false }, { false, false } }) do
                local f = fixture(stream, { enabled = flags[1], allowed = flags[2] })
                f:balance()
                H.equal(f.lookup[KEY], 5)
                H.equal(f.first.damage_profile, SOURCE)
                H.equal(f.second.damage_profile, SOURCE)
                H.truthy(f.mod[OWNER].validate())
            end
        end)
        H.test(prefix .. "idempotent install preserves exact rows and callback", function()
            local f = fixture(stream)
            local owner = assert(f:install())
            local unchanged = f:unchanged()
            local again, reason = f:install()
            H.equal(again, owner)
            H.equal(reason, "already-installed")
            unchanged()
        end)
        H.test(prefix .. "later valid lookup append preserves this owner and catalog", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local owner = assert(f:install())
            local identity = assert(wire.build_wire_identity(f.mod[FALLBACK], f.lookup, f.profiles))
            local helper = f.mod:dofile("scripts/mods/" .. stream.ns .. "/_lib_network_lookup")
            H.equal(helper.register(f.lookup, "later-profile"), 5)
            H.truthy(owner.validate())
            H.truthy(owner.apply())
            H.equal(f.first.damage_profile, KEY)
            H.equal(f.lookup[KEY], 4)
            H.equal(wire.build_wire_identity(f.mod[FALLBACK], f.lookup, f.profiles), identity)
        end)
        H.test(prefix .. "on off and throwing setting/parity readers fail closed", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local owner = assert(f:install())
            local axis = snapshot({ f.lookup, f.powers, f.donor })
            H.equal(f.first.damage_profile, KEY)
            f.enabled = false; H.truthy(owner.apply()); H.equal(f.first.damage_profile, SOURCE)
            f.enabled = true; H.truthy(owner.apply()); H.equal(f.first.damage_profile, KEY)
            f.setting_error = "setting-reader"; H.truthy(owner.apply()); H.equal(f.first.damage_profile, SOURCE)
            f.setting_error = nil; H.truthy(owner.apply()); H.equal(f.first.damage_profile, KEY)
            f.parity_error = "parity-reader"; H.truthy(owner.apply()); H.equal(f.first.damage_profile, SOURCE)
            f.parity_error = nil; f.mod._wt431_profiles_allowed = nil
            H.truthy(owner.apply()); H.equal(f.first.damage_profile, SOURCE)
            axis()
        end)
        local invalid = {
            { "missing profile registry", function(f) f.globals.DamageProfileTemplates = false end },
            { "missing power registry", function(f) f.globals.PowerLevelTemplates = false end },
            { "missing network", function(f) f.globals.NetworkLookup = false end },
            { "missing weapons", function(f) f.globals.Weapons = false end },
            { "missing axis", function(f) f.network.damage_profiles = false end },
            { "missing donor", function(f) f.profiles[SOURCE] = nil end },
            { "missing punch", function(f) f.actions.action_one.punch = nil; f.actions.action_two.punch = nil end },
            { "foreign punch", function(f) f.first.damage_profile = "foreign" end },
            { "malformed punch", function(f) f.actions.action_one.punch = false end },
            { "foreign profile", function(f) f.profiles[KEY] = { foreign = true } end },
            { "partial fallback", function(f) f.mod[FALLBACK] = { [KEY] = SOURCE } end },
            { "malformed fallback", function(f) f.mod[FALLBACK] = false end },
            { "partial reverse", function(f) f.lookup[KEY] = 4 end },
            { "foreign full tuple", function(f)
                f.lookup[4], f.lookup[KEY] = KEY, 4
                f.profiles[KEY] = clone(f.donor); f.mod[FALLBACK] = { [KEY] = SOURCE }
            end },
            { "sparse axis", function(f) f.lookup[5], f.lookup.foreign = "foreign", 5 end },
            { "asymmetric axis", function(f) f.lookup.shot_sniper = 99 end },
            { "unpaired source", function(f) f.lookup[2], f.lookup[SOURCE] = "other", nil; f.lookup.other = 2 end },
            { "missing PLT ref", function(f) f.donor.default_target = "missing" end },
            { "sparse targets", function(f) f.donor.targets[3] = clone(f.powers.default_ref) end },
            { "malformed target", function(f) f.donor.default_target.power_distribution.attack = "bad" end },
            { "nonfinite target", function(f) f.donor.targets[1].power_distribution.impact = math.huge end },
            { "overflow target", function(f) f.donor.targets[1].power_distribution.impact = 1e308 end },
            { "cyclic donor", function(f) f.donor.self = f.donor end },
            { "nonfinite donor key", function(f) f.donor[math.huge] = "foreign" end },
            { "foreign callback", function(f) f.mod[CALLBACK] = function() end end },
            { "foreign owner", function(f) f.mod[OWNER] = {} end },
            { "inherited callback", function(f) setmetatable(f.mod, { __index = { [CALLBACK] = function() end } }) end },
            { "inherited fallback", function(f) setmetatable(f.mod, { __index = { [FALLBACK] = {} } }) end },
        }
        for _, row in ipairs(invalid) do
            H.test(prefix .. "rejects " .. row[1] .. " without raw mutation", function()
                local f = fixture(stream); row[2](f); rejected(f)
            end)
        end
        for _, fault in ipairs({ "throw", "mutate-throw", "wrong-content", "retained" }) do
            H.test(prefix .. "clone isolation " .. fault, function()
                local f, held = fixture(stream), nil
                local deps = { clone = function(input)
                    H.truthy(input ~= f.donor)
                    H.truthy(input.default_target ~= f.donor.default_target)
                    held = input
                    if fault == "throw" then error("clone") end
                    if fault == "mutate-throw" then input.default_target.power_distribution.attack = -5; error("clone") end
                    if fault == "wrong-content" then input.charge_value = "foreign" end
                    return input
                end }
                if fault == "retained" then
                    assert(f:install(deps))
                    held.default_target.power_distribution.attack = 999
                    H.equal(f.profiles[KEY].default_target.power_distribution.attack, 0.25)
                else rejected(f, deps) end
                H.truthy(held, "injected clone boundary must actually run")
            end)
        end
        for _, fault in ipairs({ "throw", "mutate-throw", "foreign-write", "no-op", "wrong-index" }) do
            H.test(prefix .. "canonical helper shadow isolation " .. fault, function()
                local f, calls = fixture(stream), 0
                local real = f.mod:dofile("scripts/mods/" .. stream.ns .. "/_lib_network_lookup")
                rejected(f, { lookup = { register = function(axis, name)
                    calls = calls + 1
                    H.truthy(axis ~= f.lookup)
                    if fault == "throw" then error("helper") end
                    if fault == "mutate-throw" then axis[1] = "bad"; error("helper") end
                    if fault == "no-op" then return 4, true end
                    local index, inserted, reason = real.register(axis, name)
                    if fault == "foreign-write" then axis[1] = "bad" end
                    if fault == "wrong-index" then index = 100 end
                    return index, inserted, reason
                end } })
                H.truthy(calls > 0, "injected canonical helper boundary must actually run")
            end)
        end
        H.test(prefix .. "helper loader exception does not publish", function()
            local f = fixture(stream)
            f.mod.dofile = function() error("helper-load") end
            rejected(f)
        end)
        H.test(prefix .. "throwing dependency reader does not publish", function()
            local f = fixture(stream)
            rejected(f, { read = function(target, key)
                if key == SOURCE then error("source-read") end
                return rawget(target, key)
            end })
        end)
        for _, fault in ipairs({ "throw", "drop", "store-throw" }) do
            for stage = 1, 9 do
                H.test(prefix .. "atomic commit " .. fault .. " at write " .. stage, function()
                    local f, count = fixture(stream, { enabled = true, allowed = true }), 0
                    setmetatable(f.lookup, { __index = function() error("strict-axis") end })
                    setmetatable(f.profiles, { __index = function() error("strict-profiles") end })
                    rejected(f, { write = function(target, key, value)
                        count = count + 1
                        if count == stage then
                            if fault == "store-throw" then rawset(target, key, value) end
                            if fault ~= "drop" then error("write-fault") end
                            return
                        end
                        rawset(target, key, value)
                    end })
                    H.truthy(count >= stage, "fault stage must be reached")
                end)
            end
        end
        H.test(prefix .. "existing strict fallback survives failed commit exactly", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            f.mod[FALLBACK] = setmetatable({ unrelated = "native" }, { __index = function() error("strict-map") end })
            rejected(f, { write = function(target, key, value)
                rawset(target, key, value)
                if key == CALLBACK then error("callback-write") end
            end })
        end)
        H.test(prefix .. "ready latch is set only after full retained tuple", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local custom_writes = 0
            local owner = assert(f:install({ write = function(target, key, value)
                if key == "damage_profile" and value == KEY then
                    H.equal(f.mod[OWNER].ready, true)
                    H.equal(rawget(f.profiles, KEY), f.profiles[KEY])
                    H.equal(rawget(f.lookup, KEY), 4)
                    H.equal(rawget(f.lookup, 4), KEY)
                    H.equal(rawget(f.mod[FALLBACK], KEY), SOURCE)
                    custom_writes = custom_writes + 1
                end
                rawset(target, key, value)
            end }))
            H.equal(custom_writes, 2)
            H.truthy(owner.validate())
        end)
        H.test(prefix .. "pre-ready callback cannot repoint custom action", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local before_ready = false
            assert(f:install({ write = function(target, key, value)
                rawset(target, key, value)
                if key == CALLBACK then
                    H.equal(f.mod[OWNER].ready, false)
                    H.truthy(value())
                    H.equal(f.first.damage_profile, SOURCE)
                    H.equal(f.second.damage_profile, SOURCE)
                    before_ready = true
                end
            end }))
            H.truthy(before_ready)
            H.equal(f.first.damage_profile, KEY)
        end)
        for _, fault in ipairs({ "profile", "profile-meta", "axis", "fallback", "owner", "callback", "registry", "template", "action", "reader" }) do
            H.test(prefix .. "authority loss restores native action " .. fault, function()
                local f = fixture(stream, { enabled = true, allowed = true })
                local failing = false
                local owner = assert(f:install({ read = function(target, key)
                    if failing and fault == "reader" then error("reader-after-install") end
                    return rawget(target, key)
                end }))
                H.equal(f.first.damage_profile, KEY)
                if fault == "profile" then f.profiles[KEY].default_target.power_distribution.attack = 999 end
                if fault == "profile-meta" then setmetatable(f.profiles[KEY].targets[1], { __index = {} }) end
                if fault == "axis" then rawset(f.lookup, 4, "foreign") end
                if fault == "fallback" then f.mod[FALLBACK][KEY] = "foreign" end
                if fault == "owner" then rawset(f.mod, OWNER, nil) end
                if fault == "callback" then rawset(f.mod, CALLBACK, nil) end
                if fault == "registry" then f.globals.DamageProfileTemplates = {} end
                if fault == "template" then f.weapons[TEMPLATE] = { actions = {} } end
                if fault == "action" then f.actions.action_one.punch = { damage_profile = "foreign" } end
                failing = true
                H.truthy(owner.apply())
                H.equal(f.first.damage_profile, SOURCE)
                H.equal(f.second.damage_profile, SOURCE)
                H.equal(owner.validate(), false)
                local again = f:install()
                H.equal(again, nil, "invalid installed owner never retries registration")
            end)
        end
        H.test(prefix .. "helper failure after engagement releases custom action", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local real = f.mod:dofile("scripts/mods/" .. stream.ns .. "/_lib_network_lookup")
            local fail = false
            local owner = assert(f:install({ lookup = { register = function(...)
                if fail then error("late-helper") end
                return real.register(...)
            end } }))
            H.equal(f.first.damage_profile, KEY)
            fail = true
            H.truthy(owner.apply())
            H.equal(f.first.damage_profile, SOURCE)
            H.equal(owner.validate(), false)
        end)
        H.test(prefix .. "failed release write cannot retain custom action", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local fail = false
            local owner = assert(f:install({ write = function(target, key, value)
                if fail and key == "damage_profile" then error("release-write") end
                rawset(target, key, value)
            end }))
            fail = true; f.allowed = false
            H.equal(owner.apply(), false)
            H.equal(f.first.damage_profile, SOURCE)
            H.equal(f.second.damage_profile, SOURCE)
        end)
        H.test(prefix .. "raw nil action and inherited cells restore on failed commit", function()
            local f = fixture(stream)
            rawset(f.first, "damage_profile", nil)
            setmetatable(f.first, { __index = { damage_profile = SOURCE }, __newindex = function() error("must-rawset") end })
            rejected(f, { write = function(target, key, value)
                rawset(target, key, value)
                if target == f.second then error("last-action") end
            end })
            H.equal(rawget(f.first, "damage_profile"), nil)
            H.equal(f.first.damage_profile, SOURCE)
        end)
        H.test(prefix .. "foreign replacement action is never clobbered", function()
            local f = fixture(stream, { enabled = true, allowed = true })
            local owner = assert(f:install())
            f.first.damage_profile = "foreign"
            H.equal(owner.apply(), false)
            H.equal(f.first.damage_profile, "foreign")
            H.equal(f.second.damage_profile, SOURCE)
        end)
        H.test(prefix .. "real runtime-check module registers and invokes retained-state check", function()
            local f = fixture(stream)
            local checks, names = {}, {}
            local runtime = f.mod:dofile("scripts/mods/" .. stream.ns .. "/_wt_runtime_checks")
            local deps = {}
            if stream.id == "wt_dev" then
                deps.dev_hold_pose = {}
                deps.hold_pose_checks = f.mod:dofile("scripts/mods/" .. stream.ns .. "/_wt_runtime_checks_hold_pose")
            end
            runtime.install(f.mod, function(name, check)
                H.equal(checks[name], nil, "singleton runtime check")
                checks[name], names[#names + 1] = check, name
            end, deps)
            H.equal(#names, stream.id == "wt" and 61 or 71)
            local selected, selected_at = checks.wt_priest_punch_buff_wired
            for index, name in ipairs(names) do
                if name == "wt_priest_punch_buff_wired" then selected_at = index end
            end
            H.truthy(selected)
            H.equal(names[selected_at + 1], "wt_traced_hook_present", "old registration position")
            H.truthy(type(selected()) == "string", "missing owner is FAIL, never SKIP")
            local owner = assert(f:install())
            local unchanged = f:unchanged()
            H.equal(selected(), nil)
            unchanged()
            for _, fault in ipairs({ "power", "axis", "fallback", "callback", "validate" }) do
                local current = fixture(stream)
                local current_owner = assert(current:install())
                local current_selected, reached
                runtime.install(current.mod, function(name, check)
                    if name == "wt_priest_punch_buff_wired" then current_selected = check end
                end, deps)
                H.equal(current_selected(), nil, "each mutation starts from healthy real state")
                if fault == "power" then current.profiles[KEY].targets[1].power_distribution.attack = 999 end
                if fault == "axis" then rawset(current.lookup, rawget(current.lookup, KEY), "foreign") end
                if fault == "fallback" then rawset(current.mod[FALLBACK], KEY, "foreign") end
                if fault == "callback" then rawset(current.mod, CALLBACK, nil) end
                if fault == "validate" then rawset(current_owner, "validate", function()
                    reached = true; error("validate-read")
                end) end
                local no_writes = current:unchanged()
                local result = current_selected()
                H.truthy(type(result) == "string" and not result:find("skip:", 1, true))
                if fault == "validate" then H.truthy(reached, "throwing owner must actually execute") end
                no_writes()
            end
        end)
    end
    H.test("Priest owner mirrors only its loader namespace", function()
        local function read(path)
            local file = assert(io.open(path, "rb")); local bytes = file:read("*a"); file:close(); return bytes
        end
        local first = read(streams[1].dir .. "_wt_priest_punch_owner.lua")
        local second = read(streams[2].dir .. "_wt_priest_punch_owner.lua")
        H.equal(second:gsub("scripts/mods/weapon_tweaker_dev/", "scripts/mods/weapon_tweaker/"), first)
    end)
    return { fixture = fixture, streams = streams, wire = wire, snapshot = snapshot }
end
