-- #428 closed native-template Greataxe construction and exact item/seed admission.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_greataxe_construction_harness.lua")
    local TARGET, DONOR = "cwv_greataxe_template", "two_handed_axes_template_1"
    local function healthy(c)
        H.truthy(c.greataxe_template); H.equal(c.greataxe_owner.check(), nil)
        local _, item, seed, id = c.greataxe_items()
        H.truthy(item); H.truthy(seed); H.equal(id, "cwv_es_greataxe_001")
        H.equal(item.template, TARGET); H.equal(seed.template, TARGET); H.equal(seed.mod_data.power_level, 5)
    end
    local function denied(c)
        local _, item, seed = c.greataxe_items(); H.equal(item, nil); H.equal(seed, nil)
        H.truthy(c.greataxe_owner == nil or c.greataxe_owner.check())
    end
    local function equivalent(a, b)
        local ab, ba = {}, {}
        local function visit(left, right, where)
            H.equal(type(left), type(right), where .. " type")
            if type(left) == "function" then H.equal(string.dump(left), string.dump(right), where .. " callback"); return end
            if type(left) ~= "table" then H.equal(left, right, where .. " scalar/false"); return end
            if ab[left] then H.truthy(rawequal(ab[left], right), where .. " alias"); H.truthy(rawequal(ba[right], left)); return end
            H.equal(ba[right], nil); ab[left], ba[right] = right, left
            H.truthy(rawequal(getmetatable(left), getmetatable(right)), where .. " meta")
            local one, two = 0, 0
            for key, value in next, left do one = one + 1; visit(value, rawget(right, key), where .. "." .. tostring(key)) end
            for _ in next, right do two = two + 1 end; H.equal(one, two, where .. " raw shape")
        end
        visit(a, b, "native-Greataxe")
    end
    local function callbacks(c)
        local result, count = {}, 0
        c.env.ScriptUnit = { extension = function(_, system)
            H.equal(system, "status_system"); return { fatigued = function() return c.fatigued end }
        end }
        for group, rows in next, c.greataxe_template.actions do if type(rows) == "table" then
            for name, action in next, rows do if type(action) == "table" then
                for key, fn in next, action do if type(fn) == "function" then
                    count = count + 1; local values = {}
                    if key == "anim_end_event_condition_func" then
                        for _, reason in ipairs({ "new_interupting_action", "interrupted", "action_complete" }) do values[#values + 1] = fn({}, reason) end
                    elseif key == "enter_function" or key == "chain_condition_func" then
                        local input = { reset_release_input = function() values[#values + 1] = "reset"; return "released" end,
                            reset_release_input_with_delay = function(_, delay) values[#values + 1] = delay; return "delayed" end }
                        c.fatigued = false; values.first = fn({}, input, 0.75)
                        c.fatigued = true; values.second = fn({}, input, 0.5)
                    else error("required unexercised native callback " .. key) end
                    result[group .. "." .. name .. "." .. key] = values
                end end
            end end
        end end
        H.truthy(count > 0); return result, count
    end
    H.test("#428 Greataxe complete prior current native graph callbacks zero profile publication equivalent", function()
        local old, now = F.new(H, root, { prior = true }), F.new(H, root)
        healthy(now)
        equivalent(now.greataxe_template, old.greataxe_template)
        equivalent(now.greataxe_source, old.greataxe_source)
        local a, n = callbacks(now); local b, m = callbacks(old); H.deep_equal(a, b); H.equal(n, m)
        F.no_profile_mutations(H, now)
        H.truthy(now.graph.intact(now.greataxe_before.proofs.weapons) == false, "only template registry addition is expected")
        H.equal(#F.prior_source(root), 68110)
        local Short = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua")
        local Elven = dofile(root .. "/qa/lua/fixtures/cwv_elven_shield_construction_harness.lua")
        H.equal(#Short.prior_source(root), 66493); H.equal(#Elven.prior_source(root), 67523)
    end)
    H.test("#428 Greataxe SAME foreign template rejects actual item and seed preserving exact raw graph", function()
        local foreign = { marker = {}, actions = { action_one = { default = { damage_profile = "foreign_unregistered_greataxe_profile" } } } }
        local c = F.new(H, root, { before = function(c) c.env.Weapons[TARGET] = foreign end })
        denied(c); H.truthy(rawequal(c.env.Weapons[TARGET], foreign))
        for key, same in next, c.greataxe_unchanged do H.truthy(same, "complete immediate preservation " .. key) end
        F.no_profile_mutations(H, c)
    end)
    H.test("#428 Greataxe foreign false destination is not nil absence", function()
        local c = F.new(H, root, { before = function(c) c.env.Weapons[TARGET] = false end })
        denied(c); H.equal(rawget(c.env.Weapons, TARGET), false)
        for key, same in next, c.greataxe_unchanged do H.truthy(same, key) end
    end)
    local function rollback(c)
        denied(c); H.equal(rawget(c.env.Weapons, TARGET), nil)
        for key, same in next, c.greataxe_unchanged do H.truthy(same, "exact failed transaction " .. key) end
        F.no_profile_mutations(H, c)
    end
    for _, phase in ipairs({ "before", "write", "readback", "finalize" }) do
        local edge = phase
        H.test("#428 Greataxe single template transaction rollback " .. edge, function()
            local observed = false
            local c = F.new(H, root, {
                options = function(options)
                    if edge == "write" then options.write = function(t, k, v, tag)
                        H.equal(tag, "template"); observed = true; rawset(t, k, v); error("write failed") end
                    elseif edge == "readback" then options.read = function(_, _, tag)
                        H.equal(tag, "template"); observed = true; return false end end
                end,
                mechanics = function(graph)
                    if edge ~= "before" and edge ~= "finalize" then return graph end
                    return { capture = graph.capture, intact = graph.intact, disjoint = graph.disjoint,
                        commit = function(changes, before, after, read, write)
                            H.equal(#changes, 1)
                            return graph.commit(changes, function() before(); if edge == "before" then observed = true; error("before failed") end end,
                                function() after(); if edge == "finalize" then observed = true; error("finalizer failed") end end, read, write)
                        end }
                end,
            })
            H.truthy(observed); rollback(c)
        end)
    end
    H.test("#428 Greataxe intervening foreign destination is preserved without any attempted write", function()
        local foreign, writes = {}, 0
        local c = F.new(H, root, { after_prepare = function(c) c.env.Weapons[TARGET] = foreign end,
            options = function(options) options.write = function(...) writes = writes + 1; rawset(...) end end })
        denied(c); H.equal(writes, 0); H.truthy(rawequal(c.env.Weapons[TARGET], foreign)); F.no_profile_mutations(H, c)
    end)
    H.test("#428 Greataxe source absence and unsupported initial metatable fail closed", function()
        for _, mode in ipairs({ "nil", "false", "meta" }) do
            local c = F.new(H, root, { before = function(c)
                if mode == "nil" then c.env.Weapons[DONOR] = nil
                elseif mode == "false" then c.env.Weapons[DONOR] = false
                else setmetatable(c.greataxe_source, { __index = { foreign = true } }) end
            end })
            denied(c); H.equal(rawget(c.env.Weapons, TARGET), nil)
        end
    end)
    H.test("#428 Greataxe preparation source edit denies while preserving external source change", function()
        local c = F.new(H, root, { after_prepare = function(c) c.greataxe_source.review_external = false end })
        denied(c); H.equal(c.greataxe_source.review_external, false); H.equal(c.env.Weapons[TARGET], nil)
        F.no_profile_mutations(H, c)
    end)
    for _, mode in ipairs({ "source", "owned", "source-meta", "owned-meta", "registry-root", "registry-meta", "policy" }) do
        local axis = mode
        H.test("#428 Greataxe retained exact admission rejects " .. axis, function()
            local c = F.new(H, root); healthy(c)
            if axis == "source" then c.greataxe_source.review_external = true
            elseif axis == "owned" then c.greataxe_template.actions.action_one.default.review_external = true
            elseif axis == "source-meta" then setmetatable(c.greataxe_source, {})
            elseif axis == "owned-meta" then setmetatable(c.greataxe_template, {})
            elseif axis == "registry-root" then c.env.Weapons = c.env.table.clone(c.env.Weapons, true)
            elseif axis == "registry-meta" then setmetatable(c.env.Weapons, {})
            else c.greataxe_options.family.DEFAULT_CAREERS[1] = "wh_captain" end
            denied(c)
        end)
    end
    H.test("#428 Greataxe raw equal comparing foreign managed replacement cannot inherit authority", function()
        local c = F.new(H, root); healthy(c)
        local other = c.env.table.clone(c.greataxe_template, true)
        local meta = { __eq = function() return true end }
        setmetatable(c.greataxe_template, meta); setmetatable(other, meta); c.env.Weapons[TARGET] = other
        H.equal(c.greataxe_template == other, true); H.equal(rawequal(c.greataxe_template, other), false); denied(c)
    end)
    H.test("#428 Greataxe owned nil false replacement and foreign ItemMaster record deny both routes", function()
        for _, mode in ipairs({ "nil", "false", "item" }) do
            local c = F.new(H, root); healthy(c)
            if mode == "nil" then c.env.Weapons[TARGET] = nil
            elseif mode == "false" then c.env.Weapons[TARGET] = false
            else c.env.ItemMasterList.cwv_es_greataxe = { foreign_saved = true } end
            local _, item, seed = c.greataxe_items(); H.equal(item, nil); H.equal(seed, nil)
            if mode == "item" then H.equal(c.env.ItemMasterList.cwv_es_greataxe.foreign_saved, true) end
        end
    end)
    H.test("#428 Greataxe private factory disconnection denies real builder and seed", function()
        local c = F.new(H, root, { disconnected = true }); denied(c); H.equal(c.env.Weapons[TARGET], nil)
    end)
    H.test("#428 Greataxe captured graph envelope functions and bootstrap admission are immutable", function()
        local c = F.new(H, root); healthy(c)
        H.equal(c.greataxe_loads._cwv_greataxe_construction_owner, 1); H.equal(c.greataxe_loads._cwv_core_templates, 1)
        H.equal(c.greataxe_checks.issue428_greataxe_construction(), nil)
        c.graph.intact, c.career_envelope.intact = function() error("late graph") end, function() error("late envelope") end
        c.greataxe_options.weapons = function() return {} end
        c.core.greataxe_construction.admit_greataxe = function() return false end
        healthy(c)
    end)
    for _, id in ipairs({ "wt", "wt_dev" }) do
        local provider_id = id
        H.test("#428 Greataxe supported shared " .. provider_id .. " source target install release", function()
            local provider, mods = {}, {}
            local c = F.new(H, root, { get_mod = function(key) return mods[key] end, before = function(c)
                c.env.ActionTemplates.action_career_wh_2 = { default = { kind = "career_dummy" } }
                c.env.CareerSettings = { wh_bountyhunter = { activated_ability = { { action_name = "action_career_wh_2" } } } }
            end })
            mods[provider_id] = provider
            local integration = c.T.run(c.T.read(root .. "/tools/shared_lib/_lib_career_weapon_actions.lua"), c.env)
            local owner = "weapon_tweaker:" .. tostring(provider)
            healthy(c)
            for _, template in ipairs({ c.greataxe_source, c.greataxe_template }) do
                H.truthy(integration.install(template, { "wh_bountyhunter" }, c.env.CareerSettings, c.env.ActionTemplates, owner).ok)
                healthy(c)
                H.truthy(integration.install(template, { "wh_bountyhunter" }, c.env.CareerSettings, c.env.ActionTemplates, "character_weapon_variants").ok)
                healthy(c); integration.release(template, owner); healthy(c)
                integration.release(template, "character_weapon_variants"); healthy(c)
            end
        end)
    end
    H.test("#428 Greataxe unknown career claimant does not inherit supported owner authority", function()
        local c = F.new(H, root, { before = function(c)
            c.env.ActionTemplates.action_career_wh_2 = { default = { kind = "career_dummy" } }
            c.env.CareerSettings = { wh_bountyhunter = { activated_ability = { { action_name = "action_career_wh_2" } } } }
        end })
        local integration = c.T.run(c.T.read(root .. "/tools/shared_lib/_lib_career_weapon_actions.lua"), c.env)
        H.truthy(integration.install(c.greataxe_source, { "wh_bountyhunter" }, c.env.CareerSettings,
            c.env.ActionTemplates, "weapon_tweaker:outside-private-fixture").ok)
        denied(c)
    end)
    H.test("#428 Greataxe required inverse rejects missing corrupt input with original targets retained", function()
        local function read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s end
        local inverse = root .. "/qa/lua/fixtures/cwv_greataxe_producer_prior.reverse.patch"
        H.equal(pcall(F.prior_source, root, function(path) if path == inverse then error("missing") end; return read(path) end), false)
        H.equal(pcall(F.prior_source, root, function(path)
            local s = read(path); if path == inverse then return (s:gsub("\n%-", "\n-corrupted-", 1)) end; return s
        end), false)
    end)
    H.test("#428 Greataxe canonical preflight binds portable native and complete prior before discovery", function()
        local file = assert(io.open(root .. "/qa/check_lua_unit_tests.ps1", "rb")); local source = file:read("*a"); file:close()
        source = source:gsub("\r\n", "\n")
        local declaration = assert(source:find('function Assert-GreataxePriorCoreIdentity {', 1, true))
        H.truthy(source:find('215cfae8dca6a05008c783c9b1773b7d8ad801665538c013cdf5246bce2001d2', declaration, true))
        H.truthy(source:find('$bytes.Length -ne 68110', declaration, true))
        H.truthy(source:find('d110baa4df99a212ab1f14a62fd127ace8a96dac4dd4a13f7c32eeff2460309d', declaration, true))
        local invoke = assert(source:find('        Assert-GreataxePriorCoreIdentity -LuaExecutable $luaExe -Exporter $greataxeExporter', declaration, true))
        local guarded = assert(source:find('try {\n    if (-not $SelfTest)', declaration, true))
        local inventory = assert(source:find('[void][IO.Directory]::CreateDirectory($inventoryRoot)', invoke, true))
        H.truthy(guarded < invoke and invoke < inventory)
    end)
    H.test("#428 Greataxe native oracle detects callback alias and meta drift without host mutations", function()
        local host = {}
        for _, value in ipairs({ _G, table, io, package, package.loaded }) do
            local row = { value = value, meta = getmetatable(value), fields = {} }
            for k, v in next, value do row.fields[k] = v end; host[#host + 1] = row
        end
        local old, now = F.new(H, root, { prior = true }), F.new(H, root)
        equivalent(now.greataxe_template, old.greataxe_template)
        local action = now.greataxe_template.actions.action_one.default
        local callback = action.anim_end_event_condition_func
        action.anim_end_event_condition_func = function() return false end
        H.equal(pcall(equivalent, now.greataxe_template, old.greataxe_template), false)
        action.anim_end_event_condition_func = callback
        setmetatable(now.greataxe_template, {}); H.equal(pcall(equivalent, now.greataxe_template, old.greataxe_template), false)
        setmetatable(now.greataxe_template, nil)
        local alias = now.greataxe_source.actions.action_one.heavy_attack_right.hit_mass_count
        if alias then
            H.truthy(rawequal(alias, now.greataxe_source.actions.action_one.heavy_attack_left.hit_mass_count), "native shared hit mass alias")
            now.greataxe_source.actions.action_one.heavy_attack_right.hit_mass_count = now.env.table.clone(alias, true)
            H.equal(pcall(equivalent, now.greataxe_source, old.greataxe_source), false)
        else error("native shared hit mass alias required") end
        for _, row in ipairs(host) do
            H.truthy(rawequal(getmetatable(row.value), row.meta))
            for k, v in next, row.fields do H.truthy(rawequal(rawget(row.value, k), v), "host raw cell") end
            for k, v in next, row.value do H.truthy(rawequal(rawget(row.fields, k), v), "host added cell") end
        end
    end)
end
