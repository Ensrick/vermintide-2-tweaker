-- #428 complete Elven Shield transaction/private admission, no external inputs.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_elven_shield_construction_harness.lua")
    local PREFIX, TARGET = "cwv_ess_", "elven_sword_shield_template"
    local names = { "shield_slam", "medium_slashing_tank_1h", "medium_slashing_smiter_stab_1h",
        "light_slashing_linesman", "light_slashing_smiter_stab", "light_slashing_linesman_flat" }
    local function healthy(c)
        H.truthy(c.ess_template, c.ess_owner and c.ess_owner.check()); H.equal(c.ess_owner.check(), nil)
        for _, row in ipairs(c.ess_items()) do H.truthy(row.item); H.truthy(row.seed) end
    end
    local function denied(c)
        for _, row in ipairs(c.ess_items()) do H.equal(row.item, nil); H.equal(row.seed, nil) end
        H.equal(rawget(c.env.Weapons, TARGET), nil)
        H.truthy(c.ess_owner == nil or c.ess_owner.check())
    end
    local function equivalent(a, b)
        local ab, ba = {}, {}
        local function visit(left, right, path)
            H.equal(type(left), type(right), path .. " type")
            if type(left) == "function" then H.equal(string.dump(left), string.dump(right), path .. " callback bytecode"); return end
            if type(left) ~= "table" then H.equal(left, right, path .. " scalar/false"); return end
            if ab[left] then H.equal(rawequal(ab[left], right), true, path .. " alias"); H.equal(rawequal(ba[right], left), true); return end
            H.equal(ba[right], nil, path .. " reverse alias"); ab[left], ba[right] = right, left
            H.equal(getmetatable(left), getmetatable(right), path .. " exact meta")
            local one, two = 0, 0
            for key, value in next, left do one = one + 1; visit(value, rawget(right, key), path .. "." .. tostring(key)) end
            for _ in next, right do two = two + 1 end; H.equal(one, two, path .. " raw shape")
        end
        visit(a, b, "prior-Elven-core")
    end
    local function callbacks(c)
        local result, count = {}, 0
        c.env.ScriptUnit = { extension = function(_, system) H.equal(system, "status_system"); return { fatigued = function() return c.fatigued end } end }
        local template = c.env.Weapons[TARGET]
        for group, rows in pairs(template.actions) do if type(rows) == "table" then for name, action in pairs(rows) do if type(action) == "table" then
            for key, fn in pairs(action) do if type(fn) == "function" then
                local transcript = {}; count = count + 1
                if key == "anim_end_event_condition_func" then
                    for _, reason in ipairs({ "new_interupting_action", "interrupted", "action_complete" }) do transcript[#transcript + 1] = fn({}, reason) end
                elseif key == "enter_function" or key == "chain_condition_func" then
                    local input = { reset_release_input = function() transcript[#transcript + 1] = "reset"; return "release" end,
                        reset_release_input_with_delay = function(_, delay) transcript[#transcript + 1] = delay; return "delayed" end }
                    c.fatigued = false; transcript.first = fn({}, input, 0.75)
                    c.fatigued = true; transcript.second = fn({}, input, 0.5)
                else error("unexercised required native callback " .. key) end
                result[group .. "." .. name .. "." .. key] = transcript
            end end
        end end end end
        H.truthy(count > 0); return result, count
    end
    local function observed(c)
        local profiles = {}; for _, name in ipairs(names) do profiles[name] = c.env.DamageProfileTemplates[PREFIX .. name] end
        return { template = c.env.Weapons[TARGET], profiles = profiles, donor = c.ess_source,
            levels = c.env.PowerLevelTemplates, lookup = c.lookup, map = c.state._cwv_damage_profile_wire_source,
            generation = c.state._cwv_damage_profile_generation, first = c.state._cwv_wire_fallback_profile_id,
            audit = F.upvalue(c.state._cwv_profile_multiplier_check, "multiplier_audit") }
    end
    H.test("#428 Elven shield complete actual prior current native math aliases callbacks IDs audit equivalent", function()
        local prior, current = F.new(H, root, { prior = true }), F.new(H, root)
        healthy(current); equivalent(observed(current), observed(prior))
        local a, n = callbacks(current); local b, m = callbacks(prior); H.deep_equal(a, b); H.equal(n, m)
        local events = {}; for _, row in ipairs(prior.construction_source_events) do if row[1]:sub(1, #PREFIX) == PREFIX then events[#events + 1] = row end end
        H.equal(#events, 7); H.deep_equal(current.ess_proof().events, events)
        H.equal(current.state._cwv_profile_multiplier_check(), nil)
        H.equal(#F.prior_source(root), 67523)
        local Short = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua")
        H.equal(#Short.prior_source(root), 66493, "unchanged original complete Shortsword authority")
    end)
    H.test("#428 Elven shield same foreign prefix denies both actual item seed rows with no partial publication", function()
        local foreign = { foreign_review_object = true }
        local c = F.new(H, root, { before = function(c) c.env.DamageProfileTemplates[PREFIX .. "light_slashing_linesman"] = foreign end })
        denied(c); H.equal(rawequal(c.env.DamageProfileTemplates[PREFIX .. "light_slashing_linesman"], foreign), true)
        for key, same in next, c.ess_raw_unchanged do H.truthy(same, "immediate full raw transaction rollback " .. key) end
        H.equal(c.ess_immediate.generation, c.ess_before.generation); H.equal(c.ess_immediate.first, c.ess_before.first)
    end)
    local function rolled_back(c)
        denied(c)
        for key, same in next, c.ess_raw_unchanged do H.truthy(same, "complete immediate rollback " .. key) end
        H.equal(c.ess_immediate.generation, c.ess_before.generation)
        H.equal(c.ess_immediate.first, c.ess_before.first)
    end
    local tags = { "generation", "fallback", "template", "preview:we_waywatcher", "preview:we_maidenguard",
        "preview:we_shade", "preview:we_thornsister", "preview:root", "audit:profiles", "audit:comparisons", "audit:failure" }
    for _, name in ipairs(names) do for _, edge in ipairs({ "source", "profile", "numeric", "reverse" }) do tags[#tags + 1] = edge .. ":" .. name end end
    for _, tag in ipairs(tags) do for _, mode in ipairs({ "write", "readback" }) do
        local target, operation = tag, mode
        H.test("#428 Elven shield rollback " .. target .. " " .. operation, function()
            local observed = false
            local c = F.new(H, root, { options = function(options)
                if operation == "write" then options.write = function(t, k, v, edge)
                    rawset(t, k, v); if edge == target then observed = true; error("injected bounded write failure") end
                end else options.read = function(t, k, edge)
                    if edge == target then observed = true; return "rejected-readback" end; return rawget(t, k)
                end end
            end })
            H.truthy(observed, "actual journal edge reached"); rolled_back(c)
        end)
    end end
    H.test("#428 Elven shield finalize throw rolls back all cells after successful native readback", function()
        local reached = false
        local c = F.new(H, root, { mechanics = function(graph)
            return { capture = graph.capture, intact = graph.intact, disjoint = graph.disjoint,
                commit = function(changes, before, after, read, write)
                    return graph.commit(changes, before, function() after(); reached = true; error("finalize failure") end, read, write)
                end }
        end })
        H.truthy(reached); rolled_back(c)
    end)
    for _, initial in ipairs({ "nil", "false", "table" }) do
        local kind = initial
        H.test("#428 Elven shield healthy and rollback preserve preview " .. kind .. " root", function()
            local function before(c)
                if kind == "false" then c.ess_source.wield_anim_career_3p = false
                elseif kind == "table" then c.ess_source.wield_anim_career_3p = { es_knight = "original-pose", nested = { flag = false } } end
            end
            local prior, current = F.new(H, root, { before = before, prior = true }), F.new(H, root, { before = before })
            healthy(current); equivalent(observed(current), observed(prior))
            local failed = F.new(H, root, { before = before, options = function(options)
                options.read = function(t, k, edge) if edge == "audit:comparisons" then return "failed" end; return rawget(t, k) end
            end })
            rolled_back(failed)
            if kind == "nil" then H.equal(rawget(failed.ess_source, "wield_anim_career_3p"), nil)
            elseif kind == "false" then H.equal(rawget(failed.ess_source, "wield_anim_career_3p"), false)
            else H.equal(failed.ess_source.wield_anim_career_3p.es_knight, "original-pose"); H.equal(failed.ess_source.wield_anim_career_3p.nested.flag, false) end
        end)
    end
    local function legacy(c)
        local profile = c.env.DamageProfileTemplates.light_slashing_linesman
        c.env.PowerLevelTemplates.review_legacy_default = profile.default_target
        profile.default_target = "review_legacy_default"
    end
    H.test("#428 Elven shield actual legacy named power row healthy equivalent retained and interposition denied", function()
        local prior, current = F.new(H, root, { before = legacy, prior = true }), F.new(H, root, { before = legacy })
        healthy(current); equivalent(observed(current), observed(prior))
        local key, foreign = PREFIX .. "review_legacy_default", { power_distribution = { attack = 999, impact = 999 } }
        current.env.PowerLevelTemplates[key] = foreign
        H.truthy(current.ess_owner.check()); for _, row in ipairs(current.ess_items()) do H.equal(row.item, nil); H.equal(row.seed, nil) end
        local injected = F.new(H, root, { before = legacy, after_prepare = function(c) c.env.PowerLevelTemplates[key] = foreign end })
        denied(injected); H.equal(rawequal(injected.env.PowerLevelTemplates[key], foreign), true)
        for _, name in ipairs({ "profiles", "lookup", "map", "weapons", "audit" }) do H.truthy(injected.ess_raw_unchanged[name]) end
        H.equal(injected.ess_immediate.generation, injected.ess_before.generation)
    end)
    for _, mode in ipairs({ "write", "readback" }) do
        local operation = mode
        H.test("#428 Elven shield rollback prepared legacy power " .. operation, function()
            local reached = false
            local c = F.new(H, root, { before = legacy, options = function(options)
                if operation == "write" then options.write = function(t, k, v, edge)
                    rawset(t, k, v); if edge == "power:cwv_ess_review_legacy_default" then reached = true; error("power write") end
                end else options.read = function(t, k, edge)
                    if edge == "power:cwv_ess_review_legacy_default" then reached = true; return false end; return rawget(t, k)
                end end
            end })
            H.truthy(reached); rolled_back(c)
        end)
    end
    H.test("#428 Elven shield foreign false profile pair map and template states are not nil", function()
        local changes = {
            function(c) c.env.DamageProfileTemplates[PREFIX .. "shield_slam"] = false end,
            function(c) c.lookup[PREFIX .. "shield_slam"] = false end,
            function(c) c.state._cwv_damage_profile_wire_source[PREFIX .. "shield_slam"] = false end,
            function(c) c.env.Weapons[TARGET] = false end,
        }
        for index, change in ipairs(changes) do
            local c = F.new(H, root, { before = change })
            for _, row in ipairs(c.ess_items()) do H.equal(row.item, nil); H.equal(row.seed, nil) end
            for _, same in next, c.ess_raw_unchanged do H.truthy(same) end
            if index == 4 then H.equal(rawget(c.env.Weapons, TARGET), false) end
        end
    end)
    H.test("#428 Elven shield preparation source mutations reject without erasing foreign edits", function()
        local c = F.new(H, root, { after_prepare = function(c)
            c.env.DamageProfileTemplates.shield_slam.default_target.power_distribution.impact = 999
        end })
        denied(c); H.equal(c.env.DamageProfileTemplates.shield_slam.default_target.power_distribution.impact, 999)
        for _, key in ipairs({ "lookup", "map", "weapons", "audit" }) do H.truthy(c.ess_raw_unchanged[key]) end
        H.equal(c.ess_immediate.generation, c.ess_before.generation)
    end)
    H.test("#428 Elven shield prepared state generation cannot overwrite an intervening update", function()
        local c = F.new(H, root, { after_prepare = function(c) c.state._cwv_damage_profile_generation = 999 end })
        denied(c); H.equal(c.ess_immediate.generation, 999)
        for _, key in ipairs({ "profiles", "levels", "lookup", "map", "weapons", "audit" }) do H.truthy(c.ess_raw_unchanged[key]) end
    end)
    H.test("#428 Elven shield preview owned and nonowner cells have retained authority", function()
        for _, alter in ipairs({ function(c) c.ess_source.wield_anim_career_3p.we_shade = "foreign" end,
            function(c) c.ess_source.wield_anim_career_3p.nested.flag = true end,
            function(c) c.ess_source.wield_anim_career_3p = {} end }) do
            local c = F.new(H, root, { before = function(c) c.ess_source.wield_anim_career_3p = { nested = { flag = false } } end })
            healthy(c); alter(c); H.truthy(c.ess_owner.check())
            for _, row in ipairs(c.ess_items()) do H.equal(row.item, nil); H.equal(row.seed, nil) end
        end
    end)
    H.test("#428 Elven shield absent private factory denies exact rows but preserves unrelated builder", function()
        local c = F.new(H, root, { disconnected = true })
        denied(c)
        local _, build = c.ess_items()
        H.truthy(build({ item_key = "review_unrelated", base_weapon = "es_sword_shield", template = "one_handed_sword_shield_template_1" }))
    end)
    H.test("#428 Elven shield bootstrap captures private admission by value and cannot be publicly overridden", function()
        local c = F.new(H, root); healthy(c)
        c.core.elven_shield_construction.admit_elven_shield = function() return true end
        c.env.DamageProfileTemplates[PREFIX .. "shield_slam"] = {}
        for _, row in ipairs(c.ess_items()) do H.equal(row.item, nil); H.equal(row.seed, nil) end
        H.truthy(c.ess_checks.issue428_elven_shield_construction())
    end)
    H.test("#428 Elven shield real shared WT and CWV career install release stays supported", function()
        local provider = {}
        local c = F.new(H, root, { get_mod = function(id) if id == "wt_dev" then return provider end end,
            before = function(c)
                c.env.ActionTemplates.action_career_wh_2 = { default = { kind = "career_dummy" } }
                c.env.CareerSettings = { wh_bountyhunter = { activated_ability = { { action_name = "action_career_wh_2" } } } }
            end })
        local integration = c.T.run(c.T.read(root .. "/tools/shared_lib/_lib_career_weapon_actions.lua"), c.env)
        local owner = "weapon_tweaker:" .. tostring(provider)
        H.truthy(integration.install(c.ess_source, { "wh_bountyhunter" }, c.env.CareerSettings, c.env.ActionTemplates, owner).ok)
        H.truthy(integration.install(c.ess_template, { "wh_bountyhunter" }, c.env.CareerSettings, c.env.ActionTemplates, "character_weapon_variants").ok)
        healthy(c); integration.release(c.ess_source, owner); integration.release(c.ess_template, "character_weapon_variants"); healthy(c)
    end)
    H.test("#428 Elven shield module once source order exact private binds and named real check", function()
        local c = F.new(H, root); healthy(c)
        H.equal(c.ess_loads._cwv_elven_shield_construction_owner, 1)
        H.equal(c.ess_loads._cwv_core_templates, 1)
        H.deep_equal(c.core_order, { "core", "musket" })
        H.equal(c.ess_checks.issue428_elven_shield_construction(), nil)
        c.ess_envelope.intact = function() error("late envelope access") end
        c.ess_options.weapons = function() return {} end
        healthy(c)
    end)
    H.test("#428 Elven shield required inverse rejects missing and corrupted sources no fallback", function()
        local native_read = io.open
        local function read(path)
            local file = assert(native_read(path, "rb")); local s = file:read("*a"); file:close(); return s
        end
        local inverse = root .. "/qa/lua/fixtures/cwv_elven_shield_greataxe_producer_prior.reverse.patch"
        local missing_hits, corrupt_hits, corruptions = 0, 0, 0
        H.equal(pcall(F.prior_source, root, function(path)
            if path == inverse then missing_hits = missing_hits + 1; error("required inverse missing") end
            return read(path)
        end), false)
        H.equal(missing_hits, 1, "missing-input injection must reach the ACTIVE required inverse")
        H.equal(pcall(F.prior_source, root, function(path)
            local s = read(path)
            if path == inverse then
                corrupt_hits = corrupt_hits + 1
                local count; s, count = s:gsub("%-local", "-corrupt-local", 1)
                corruptions = corruptions + count
            end
            return s
        end), false)
        H.equal(corrupt_hits, 1, "corruption injection must reach the ACTIVE required inverse")
        H.equal(corruptions, 1, "one consumed inverse source statement must actually be corrupted")
    end)
    H.test("#428 Elven shield complete native oracle catches sharing callback meta faults and preserves host shape", function()
        local host = {}
        for _, t in ipairs({ _G, table, io, package, package.loaded }) do
            local row = { target = t, meta = getmetatable(t), fields = {} }
            for k, v in next, t do row.fields[k] = v end; host[#host + 1] = row
        end
        local prior, current = F.new(H, root, { prior = true }), F.new(H, root)
        local function native_graph(c)
            local sources = {}; for _, name in ipairs(names) do sources[name] = c.env.DamageProfileTemplates[name] end
            return { sources = sources, levels = c.env.PowerLevelTemplates }
        end
        equivalent(native_graph(current), native_graph(prior))
        local profile = current.env.DamageProfileTemplates.shield_slam
        local original = profile.default_target
        H.equal(rawequal(original, current.env.PowerLevelTemplates.default_target_slam_tank_M), true, "actual native alias is exercised")
        profile.default_target = current.env.table.clone(original, true)
        H.equal(pcall(equivalent, native_graph(current), native_graph(prior)), false, "source alias split must fail whole oracle")
        profile.default_target = original
        local action = current.ess_template.actions.action_one.default
        local callback = action.anim_end_event_condition_func
        action.anim_end_event_condition_func = function() return false end
        H.equal(pcall(equivalent, observed(current), observed(prior)), false, "native callback disconnection must fail")
        action.anim_end_event_condition_func = callback
        setmetatable(current.ess_template, {})
        H.equal(pcall(equivalent, observed(current), observed(prior)), false, "metatable disconnection must fail")
        setmetatable(current.ess_template, nil); healthy(current)
        for _, row in ipairs(host) do
            H.equal(rawequal(getmetatable(row.target), row.meta), true)
            for k, v in next, row.fields do H.equal(rawequal(rawget(row.target, k), v), true, "host raw cell") end
            for k, v in next, row.target do H.equal(rawequal(rawget(row.fields, k), v), true, "host added cell") end
        end
    end)
    H.test("#428 Elven shield canonical gate requires fixed native and whole prior identity before inventory", function()
        local file = assert(io.open(root .. "/qa/check_lua_unit_tests.ps1", "rb")); local source = file:read("*a"); file:close()
        source = source:gsub("\r\n", "\n")
        local declaration = assert(source:find('function Assert-ElvenShieldPriorCoreIdentity {', 1, true))
        H.truthy(source:find('9c303ada988fa2ebd5c3b7c530461b9e787464cc153ac87d18687f5035f10f45', declaration, true))
        H.truthy(source:find("$bytes.Length -ne 67523", declaration, true))
        H.truthy(source:find('2aeb3673d4a05a1cd257f18a24d66c2e38e9b2a3957a6dd8eb4afc8af46a7a08', declaration, true))
        local invoke = assert(source:find('        Assert-ElvenShieldPriorCoreIdentity -LuaExecutable $luaExe -Exporter $elvenShieldExporter', declaration, true))
        local guarded = assert(source:find('try {\n    if (-not $SelfTest)', declaration, true))
        local inventory = assert(source:find('[void][IO.Directory]::CreateDirectory($inventoryRoot)', invoke, true))
        H.truthy(guarded < invoke and invoke < inventory)
    end)
    H.test("#428 Elven shield preexisting native fallback generation and later unrelated producer remain valid", function()
        local function before(c)
            c.state._cwv_damage_profile_generation = 23
            c.state._cwv_wire_fallback_profile_id = c.lookup.shot_sniper
            local name = "cwv_prior_control"
            c.env.DamageProfileTemplates[name] = c.env.table.clone(c.env.DamageProfileTemplates.shot_sniper, true)
            local id = #c.lookup + 1; c.lookup[id], c.lookup[name] = name, id
            c.state._cwv_damage_profile_wire_source[name] = "shot_sniper"
        end
        local prior, current = F.new(H, root, { prior = true, before = before }), F.new(H, root, { before = before })
        healthy(current); equivalent(observed(current), observed(prior))
        local name = "cwv_later_control"
        current.env.DamageProfileTemplates[name] = current.env.table.clone(current.env.DamageProfileTemplates.shot_sniper, true)
        local id = #current.lookup + 1; current.lookup[id], current.lookup[name] = name, id
        current.state._cwv_damage_profile_wire_source[name] = "shot_sniper"
        current.state._cwv_damage_profile_generation = current.state._cwv_damage_profile_generation + 1
        healthy(current)
        local rejected = F.new(H, root, { before = function(c) c.state._cwv_wire_fallback_profile_id = false end })
        denied(rejected); H.equal(rejected.ess_immediate.first, false)
        for _, same in next, rejected.ess_raw_unchanged do H.truthy(same) end
    end)
    return { F = F, healthy = healthy, denied = denied, equivalent = equivalent, observed = observed, callbacks = callbacks }
end
